require 'set'
require 'fileutils'
require_relative 'heap'
require_relative 'mutator'
require_relative 'mark_sweep'
require_relative 'copying'
require_relative 'generational'

module GCSim
  Checkpoint = Data.define(:label, :line, :stack, :live, :allocated, :phase, :survivors, :reachable)
  Cascade = Data.define(:line, :freed, :work)
  Pause = Data.define(:line, :work, :freed_words, :collection)

  module Analysis
    include HeapTools
    extend self

    def used_words(objects) = objects.sum(&:size)

    def fragmentation(blocks)
      total = total_free(blocks)
      pct(total - largest_free(blocks), total)
    end

    def reachable_numbers(roots)
      reached = Set.new
      stack = roots.compact
      until stack.empty?
        obj = stack.pop
        next unless reached.add?(obj.number)

        obj.fields.each { |child| stack << child if child }
      end
      reached
    end

    def leak_groups(members)
      neighbors = members.transform_values { [] }
      members.each_value do |obj|
        obj.fields.each do |child|
          next unless child && members.key?(child.number)

          neighbors[obj.number] << child.number
          neighbors[child.number] << obj.number
        end
      end
      grouped = Set.new
      members.keys.sort.filter_map do |number|
        next unless grouped.add?(number)

        group = []
        stack = [number]
        until stack.empty?
          current = stack.pop
          group << members[current]
          neighbors[current].each { |other| stack << other if grouped.add?(other) }
        end
        group.sort_by(&:number)
      end
    end

    def on_cycle?(obj, members)
      visited = Set.new
      stack = obj.fields.compact.select { |child| members.key?(child.number) }
      until stack.empty?
        current = stack.pop
        return true if current.equal?(obj)
        next unless visited.add?(current.number)

        current.fields.each do |child|
          stack << child if child && members.key?(child.number)
        end
      end
      false
    end

    def leak_report(title, garbage, deaths)
      members = garbage.to_h { |obj| [obj.number, obj] }
      groups = leak_groups(members)
      lines = ["#{title} groups #{groups.length} objects #{garbage.length} words #{used_words(garbage)}"]
      groups.each_with_index do |group, index|
        cycles = 0
        ids = group.map do |obj|
          if on_cycle?(obj, members)
            cycles += 1
            "#{obj.number}*"
          else
            obj.number.to_s
          end
        end
        died = group.map { |obj| deaths[obj.number - 1] }.max
        lines << "group #{index + 1} objects #{group.length} words #{used_words(group)} " \
                 "cycle #{cycles} died #{died} ids #{ids.join(' ')}"
      end
      lines
    end

    def free_line(blocks)
      "free total #{total_free(blocks)} largest #{largest_free(blocks)} blocks #{blocks.length} " \
        "sizes #{class_table(blocks.map(&:last))} fragmentation #{fragmentation(blocks)}"
    end

    def locality_line(objects, reachable)
      pointers = forward = backward = distance = 0
      objects.each do |obj|
        next unless reachable.include?(obj.number)

        obj.fields.each do |child|
          next unless child

          pointers += 1
          forward += 1 if child.address > obj.address
          backward += 1 if child.address < obj.address
          distance += (child.address - obj.address).abs
        end
      end
      mean = pointers.zero? ? '-' : dec2(distance, pointers)
      "locality pointers #{pointers} forward #{forward} backward #{backward} mean_distance #{mean}"
    end

    def generations_line(collector)
      young, old = Pair.new, Pair.new
      ages = Array.new(4, 0)
      collector.objects.each do |obj|
        if collector.young?(obj)
          young.add(obj)
          ages[[obj.age, 3].min] += 1
        else
          old.add(obj)
        end
      end
      "generations young #{young} old #{old} remembered #{collector.remembered.length} " \
        "ages 0:#{ages[0]} 1:#{ages[1]} 2:#{ages[2]} 3+:#{ages[3]}"
    end

    def record_line(record)
      "#{record.number} line #{record.line} size #{record.request} kind #{record.kind} " \
        "live #{record.live} freed #{record.freed} moved #{record.moved} promoted #{record.promoted} " \
        "stack #{record.stack} work #{record.work} before #{record.before.join(' ')} " \
        "after #{record.after.join(' ')}"
    end

    def join_blocks(blocks)
      blocks.each_with_index.flat_map { |block, index| index.zero? ? block : ['', *block] }
    end
  end

  class Script
    include Analysis
    attr_reader :commands, :deaths, :alive, :checkpoints

    LIFETIME_CLASSES = %w[0-63 64-255 256-1023 1024-4095 4096+].freeze
    LIFETIME_LIMITS = [63, 255, 1023, 4095].freeze

    def initialize(parsed_lines)
      @line_count = parsed_lines.length
      @commands, @errors, @roots, @objects = [], [], [], []
      @births, @deaths, @lifetimes, @checkpoints = [], [], [], []
      @counts = Mutator::COMMAND_NAMES.to_h { |name| [name, 0] }
      @alive, @labels = Set.new, Set.new
      @live, @peak = Pair.new, Pair.new
      @clock = @phase_start = 0
      @peak_line = nil
      parsed_lines.each_with_index do |(command, reason), index|
        reason ||= check(command)
        if reason
          @errors << [index + 1, reason]
        else
          execute(command)
        end
      end
    end

    def check(command)
      name, args = command.name, command.args
      depth = @roots.length
      return 'stack' if %w[ALLOC PUSH LOAD].include?(name) && depth == 64
      return 'stack' if %w[LOAD SET OVERWRITE].include?(name) && args[0] >= depth
      if %w[PUSH SET OVERWRITE].include?(name) && args[-1] && args[-1] >= depth
        return 'stack'
      end
      return 'stack' if name == 'POP' && args[0] > depth
      if %w[LOAD SET].include?(name)
        target = @roots[args[0]]
        return 'null' if target.nil?
        return 'field' if args[1] >= target.fields.length
      end
      return 'duplicate' if name == 'CHECKPOINT' && @labels.include?(args[0])

      nil
    end

    def value(source) = source.nil? ? nil : @roots[source]

    def execute(command)
      name, args = command.name, command.args
      @commands << command
      @counts[name] += 1
      case name
      when 'ALLOC'
        obj = HeapObject.new(@objects.length + 1, *args)
        @objects << obj
        @births << @clock
        @deaths << nil
        @lifetimes << nil
        @clock += obj.size
        @roots << obj
      when 'PUSH' then @roots << value(args[0])
      when 'LOAD' then @roots << @roots[args[0]].fields[args[1]]
      when 'POP' then @roots.pop(args[0])
      when 'SET' then @roots[args[0]].fields[args[1]] = value(args[2])
      when 'OVERWRITE' then @roots[args[0]] = value(args[1])
      end
      reached = reachable_numbers(@roots)
      (@alive - reached).each do |number|
        obj = @objects[number - 1]
        @deaths[number - 1] = command.line
        @lifetimes[number - 1] = @clock - @births[number - 1] - obj.size
      end
      @alive = reached
      @live = Pair.new(reached.map { |number| @objects[number - 1] })
      if @peak_line.nil? || @live.words > @peak.words
        @peak = @live
        @peak_line = command.line
      end
      add_checkpoint(command) if name == 'CHECKPOINT'
    end

    def add_checkpoint(command)
      label = command.args[0]
      @labels.add(label)
      created = @objects.drop(@phase_start)
      survivors = created.select { |obj| @alive.include?(obj.number) }
      @checkpoints << Checkpoint.new(label, command.line, @roots.length, @live,
                                     Pair.new(@objects), Pair.new(created), Pair.new(survivors), @alive)
      @phase_start = @objects.length
    end

    def report
      lines = ["script lines #{@line_count} valid #{@commands.length} errors #{@errors.length}"]
      @errors.each { |line, reason| lines << "error line #{line} #{reason}" }
      lines << "commands #{Mutator::COMMAND_NAMES.map { |name| "#{name} #{@counts[name]}" }.join(' ')}"
      sizes = @objects.map(&:size)
      lines << "allocated objects #{@objects.length} words #{@clock} sizes #{class_table(sizes)}"
      lines << "peak_live objects #{@peak.count} words #{@peak.words} line #{@peak_line}"
      lines << "end_live objects #{@live.count} words #{@live.words} stack #{@roots.length}"
      counts = Array.new(LIFETIME_CLASSES.length + 1, 0)
      @lifetimes.each do |lifetime|
        index = if lifetime.nil?
                  LIFETIME_CLASSES.length
                else
                  LIFETIME_LIMITS.index { |limit| lifetime <= limit } || LIFETIME_LIMITS.length
                end
        counts[index] += 1
      end
      classes = LIFETIME_CLASSES.zip(counts).map { |label, count| "#{label} #{count}" }.join(' ')
      lines << "lifetimes #{classes} live #{counts[-1]}"
      @checkpoints.each do |checkpoint|
        lines << "checkpoint #{checkpoint.label} line #{checkpoint.line} stack #{checkpoint.stack} " \
                 "live #{checkpoint.live} allocated #{checkpoint.allocated} phase #{checkpoint.phase} " \
                 "survivors #{checkpoint.survivors} survival #{pct(checkpoint.survivors.words, checkpoint.phase.words)}"
      end
      lines
    end
  end

  class RefCounting < MarkSweep
    include Analysis
    attr_reader :increments, :decrements, :reports

    def initialize(size, deaths)
      super(size)
      @deaths = deaths
      @increments = @decrements = 0
      @released, @reports = [], []
    end

    def retain(obj)
      return if obj.nil?

      obj.count += 1
      @increments += 1
    end

    def release(obj)
      pending = [obj]
      until pending.empty?
        current = pending.pop
        next if current.nil?

        @decrements += 1
        current.count -= 1
        next unless current.count.zero?

        @objects.delete(current)
        @released << current
        # LIFO processing descends into field 0 before later fields.
        pending.concat(current.fields.reverse)
      end
    end

    def take_cascade(line)
      return if @released.empty?

      cascade = Cascade.new(line, Pair.new(@released), @released.sum { |obj| 1 + obj.fields.length })
      @released = []
      cascade
    end

    def collect(roots, line, request)
      record = new_record(line, request, 'backup')
      Marking.mark(record, roots, @objects)
      garbage = @objects.reject(&:marked)
      @reports << leak_report("backup #{record.number} line #{line}", garbage, @deaths)
      @objects = Marking.sweep(record, @objects)
      garbage.each do |obj|
        obj.fields.each do |child|
          next unless child && child.marked

          child.count -= 1
          @decrements += 1
        end
      end
      finish_record(record)
    end

    def finish(reachable)
      garbage = @objects.reject { |obj| reachable.include?(obj.number) }
      @reports << leak_report('end', garbage, @deaths)
    end
  end

  class PauseStats
    attr_reader :count, :collections, :work, :freed_words, :p50, :p90, :maximum

    def initialize(pauses)
      works = pauses.map(&:work).sort
      @count = pauses.length
      @collections = pauses.count(&:collection)
      @work = works.sum
      @freed_words = pauses.sum(&:freed_words)
      @maximum = works.last || 0
      @p50 = percentile(works, 50)
      @p90 = percentile(works, 90)
    end

    def percentile(works, rank)
      works.empty? ? '-' : works[(rank * works.length + 99) / 100 - 1]
    end
  end

  class Timeline
    include HeapTools

    def initialize
      @starts, @lengths, @flags, @mutator_before = [], [], [], []
      @length = @mutator = 0
    end

    def add(mutator, units)
      return if units.zero?

      if !@flags.empty? && @flags.last == mutator
        @lengths[-1] += units
      else
        @starts << @length
        @lengths << units
        @flags << mutator
        @mutator_before << @mutator
      end
      @length += units
      @mutator += units if mutator
    end

    def mutator_until(position)
      index = (@starts.bsearch_index { |start| start > position } || @starts.length) - 1
      @mutator_before[index] + (@flags[index] ? position - @starts[index] : 0)
    end

    def utilization = pct(@mutator, @length)

    def minimum_utilization(width)
      return '-' if width > @length

      minimum = width
      @starts.zip(@lengths).each do |start, length|
        # A minimum occurs when either edge of the window meets a segment boundary.
        [start, start + length - width].each do |first|
          next unless first >= 0 && first <= @length - width

          count = mutator_until(first + width) - mutator_until(first)
          minimum = [minimum, count].min
        end
      end
      pct(minimum, width)
    end
  end

  class Run
    include Analysis
    attr_reader :entry, :observations

    GENERATIONAL_KINDS = %w[minor major tenure full].freeze

    def initialize(entry, config, script)
      @entry, @config, @script = entry, config, script
      @collector = case entry.type
                   when 'MARK_SWEEP' then MarkSweep.new(config.heap_size)
                   when 'MARK_COMPACT' then MarkCompact.new(config.heap_size)
                   when 'COPYING' then Copying.new(config.heap_size)
                   when 'GENERATIONAL' then Generational.new(config.heap_size, entry.young, entry.age)
                   when 'REFCOUNT' then RefCounting.new(config.heap_size, script.deaths)
                   end
      @generational = entry.type == 'GENERATIONAL'
      @refcount = entry.type == 'REFCOUNT'
      @roots, @placed, @cascades, @observations = [], [], [], []
      @timeline = Timeline.new
      @peak_used = @failed_size = 0
      @failed_line = nil
    end

    def refcount? = @refcount
    def completed? = @failed_line.nil?
    def failed_before?(line) = !completed? && @failed_line < line
    def value(source) = source.nil? ? nil : @roots[source]

    def simulate
      @script.commands.each { |command| return unless step(command) }
      @collector.finish(@script.alive) if @refcount
    end

    def step(command)
      previous = @collector.records.length
      if command.name == 'ALLOC'
        obj = HeapObject.new(@placed.length + 1, *command.args)
        placed = allocate(obj, command.line)
        units = obj.size
      else
        execute(command)
        placed = true
        units = 1
      end
      @collector.records.drop(previous).each { |record| @timeline.add(false, record.work) }
      unless placed
        @failed_line, @failed_size = command.line, units
        return false
      end
      @timeline.add(true, units)
      if @refcount && (cascade = @collector.take_cascade(command.line))
        @cascades << cascade
        @timeline.add(false, cascade.work)
      end
      true
    end

    def retain(obj)
      @collector.retain(obj) if @refcount
    end

    def release(obj)
      @collector.release(obj) if @refcount
    end

    def push(obj)
      retain(obj)
      @roots << obj
    end

    def allocate(obj, line)
      return false unless @collector.allocate(obj, @roots, line)

      @placed << obj
      push(obj)
      @peak_used = [@peak_used, used_words(@collector.objects)].max
      true
    end

    def execute(command)
      args = command.args
      case command.name
      when 'PUSH' then push(value(args[0]))
      when 'LOAD' then push(@roots[args[0]].fields[args[1]])
      when 'POP' then args[0].times { release(@roots.pop) }
      when 'SET'
        target, new_value = @roots[args[0]], value(args[2])
        @collector.write_barrier(target, new_value) if @generational
        retain(new_value)
        previous = target.fields[args[1]]
        target.fields[args[1]] = new_value
        release(previous)
      when 'OVERWRITE'
        new_value = value(args[1])
        retain(new_value)
        previous = @roots[args[0]]
        @roots[args[0]] = new_value
        release(previous)
      when 'CHECKPOINT'
        @observations << observe(@script.checkpoints[@observations.length])
      end
    end

    def observe(checkpoint)
      objects, reachable = @collector.objects, checkpoint.reachable
      live = objects.select { |obj| reachable.include?(obj.number) }
      garbage = objects.reject { |obj| reachable.include?(obj.number) }
      lines = ["heap objects #{Pair.new(objects)} reachable #{Pair.new(live)} garbage #{Pair.new(garbage)}",
               free_line(@collector.free_list), locality_line(objects, reachable)]
      lines << generations_line(@collector) if @generational
      if @config.maps.include?(checkpoint.label)
        text = heap_map(@config.heap_size, objects, reachable, @collector.inactive_range)
        (0...text.length).step(@config.width) do |first|
          lines << format('%04d %s', first, text[first, @config.width])
        end
      end
      lines
    end

    def pauses
      @collector.records.map { |record| Pause.new(record.line, record.work, record.freed.words, true) } +
        @cascades.map { |cascade| Pause.new(cascade.line, cascade.work, cascade.freed.words, false) }
    end

    def generational_line
      records = @collector.records
      parts = ['generational']
      GENERATIONAL_KINDS.each do |kind|
        matching = records.select { |record| record.kind == kind }
        parts << "#{kind} #{matching.length} #{matching.sum(&:work)}"
      end
      promoted = records.reduce(Pair.new) { |pair, record| pair.merge(record.promoted) }
      parts << "promoted #{promoted} barrier #{@collector.barriers} remembered #{@collector.remembers}"
      parts.join(' ')
    end

    def refcount_line
      freed = Pair.new
      largest = nil
      @cascades.each do |cascade|
        freed.merge(cascade.freed)
        largest = cascade if largest.nil? || cascade.work > largest.work
      end
      maximum = if largest
                  "max_cascade #{largest.freed.count} #{largest.work} line #{largest.line}"
                else
                  'max_cascade 0 0 line -'
                end
      "refcount increments #{@collector.increments} decrements #{@collector.decrements} " \
        "cascades #{@cascades.length} freed #{freed} #{maximum}"
    end

    def phase_lines(all_pauses)
      previous = 0
      @script.checkpoints.map do |checkpoint|
        line = if failed_before?(checkpoint.line)
                 "phase #{checkpoint.label} out_of_memory"
               else
                 stats = PauseStats.new(all_pauses.select { |pause| pause.line > previous && pause.line <= checkpoint.line })
                 "phase #{checkpoint.label} collections #{stats.collections} pauses #{stats.count} " \
                   "work #{stats.work} freed #{stats.freed_words} max_pause #{stats.maximum}"
               end
        previous = checkpoint.line
        line
      end
    end

    def collection_block
      lines = ["collector #{@entry.name} #{@entry.type}"]
      lines.concat(@collector.records.map { |record| record_line(record) })
      all_pauses = pauses
      stats = PauseStats.new(all_pauses)
      lines << "totals collections #{stats.collections} pauses #{stats.count} work #{stats.work} " \
               "freed #{stats.freed_words} pause p50 #{stats.p50} p90 #{stats.p90} max #{stats.maximum}"
      windows = @config.windows.map { |width| "#{width}:#{@timeline.minimum_utilization(width)}" }.join(' ')
      lines << "utilization #{@timeline.utilization} mmu #{windows}"
      lines << generational_line if @generational
      lines << refcount_line if @refcount
      lines.concat(phase_lines(all_pauses))
      lines << (completed? ? 'status completed' : "status out_of_memory line #{@failed_line} size #{@failed_size}")
      lines
    end

    def summary_row
      records = @collector.records
      stats = PauseStats.new(pauses)
      moves = @placed.map(&:moves).select(&:positive?)
      if completed?
        blocks = @collector.free_list
        ending = [used_words(@collector.objects), total_free(blocks), largest_free(blocks), fragmentation(blocks)]
      else
        ending = Array.new(4, '-')
      end
      [@entry.name, @entry.type, completed? ? 'completed' : 'out_of_memory', records.length, stats.count,
       records.sum { |record| record.live.count }, records.sum { |record| record.moved.count },
       moves.length, moves.max || 0, stats.freed_words, stats.work, stats.p50, stats.p90, stats.maximum,
       @peak_used, *ending].join(',')
    end

    def leak_block
      lines = ["collector #{@entry.name}", *@collector.reports.flatten(1)]
      lines << 'status out_of_memory' unless completed?
      lines
    end
  end

  class Application
    extend Analysis

    SUMMARY_HEADER = 'collector,type,status,collections,pauses,live,moved,moved_objects,max_moves,freed,' \
                     'total_work,p50_pause,p90_pause,max_pause,peak_used,end_used,end_free,largest_free,fragmentation'

    def self.write_lines(name, lines)
      File.binwrite(File.join('output', name), lines.empty? ? '' : lines.join("\n") + "\n")
    end

    def self.run
      config = Mutator.read_config(File.join('input', 'config.txt'))
      script = Script.new(Mutator.read_script(File.join('input', 'mutator.txt')))
      runs = config.collectors.map do |entry|
        run = Run.new(entry, config, script)
        run.simulate
        run
      end
      map_blocks = script.checkpoints.each_with_index.flat_map do |checkpoint, index|
        runs.map do |run|
          ["checkpoint #{checkpoint.label} line #{checkpoint.line} collector #{run.entry.name}",
           *(run.observations[index] || ['out_of_memory'])]
        end
      end
      leak_blocks = runs.select(&:refcount?).map(&:leak_block)
      FileUtils.mkdir_p('output')
      write_lines('mutator.txt', script.report)
      write_lines('heap_maps.txt', join_blocks(map_blocks))
      write_lines('collections.txt', join_blocks(runs.map(&:collection_block)))
      write_lines('summary.csv', [SUMMARY_HEADER, *runs.map(&:summary_row)])
      write_lines('leaks.txt', leak_blocks.empty? ? ['none'] : join_blocks(leak_blocks))
    end
  end
end

GCSim::Application.run if $PROGRAM_NAME == __FILE__
