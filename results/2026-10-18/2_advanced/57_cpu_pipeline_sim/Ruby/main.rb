require_relative 'trace_io'
require_relative 'hazards'
require_relative 'pipeline'
require_relative 'predictors'
require_relative 'report'

class CpuSimulation
  include TraceIO
  include Pipeline
  include Report
  CLASSES = %w[ALU MUL LOAD STORE BRANCH JUMP NOP].freeze
  CONTROLS = %w[BRANCH JUMP].freeze
  MISS_KINDS = %w[direction btb_miss wrong_target].freeze
  OPERANDS = {
    'ALU' => %w[required required optional], 'MUL' => %w[required required required],
    'LOAD' => %w[required required none], 'STORE' => %w[none required required],
    'BRANCH' => %w[none required optional], 'JUMP' => %w[optional optional none],
    'NOP' => %w[none none none]
  }.freeze

  def check_record(line)
    tokens = line.split(/ /, -1)
    return [nil, 'fields'] if tokens.length != 8 || tokens.include?('')
    pc_text, kind, rd_text, rs1_text, rs2_text, outcome, target_text, address_text = tokens
    pc = parse_hex(pc_text)
    return [nil, 'pc'] if pc.nil? || pc % 4 != 0
    return [nil, 'class'] unless CLASSES.include?(kind)
    register_texts = [rd_text, rs1_text, rs2_text]
    registers = register_texts.map { |text| parse_register(text) }
    return [nil, 'register'] if register_texts.zip(registers).any? { |text, value| text != '-' && value.nil? }
    register_texts.zip(OPERANDS[kind]).each do |text, usage|
      return [nil, 'operands'] if (usage == 'required' && text == '-') || (usage == 'none' && text != '-')
    end
    allowed = kind == 'BRANCH' ? %w[T N] : kind == 'JUMP' ? ['T'] : ['-']
    return [nil, 'taken'] unless allowed.include?(outcome)
    target = parse_hex(target_text)
    if CONTROLS.include?(kind)
      return [nil, 'target'] if target.nil? || target % 4 != 0 || target == pc + 4
    elsif target_text != '-'
      return [nil, 'target']
    end
    address = parse_hex(address_text)
    if %w[LOAD STORE].include?(kind)
      return [nil, 'address'] if address.nil? || address % 4 != 0
    elsif address_text != '-'
      return [nil, 'address']
    end
    rd, rs1, rs2 = registers
    instruction = { pc: pc, class: kind, rd: rd, rs1: rs1, rs2: rs2,
                    outcome: outcome, target: target, address: address }
    if (previous = @static[pc])
      return [nil, 'conflict'] if %i[class rd rs1 rs2].any? { |key| instruction[key] != previous[key] }
      fixed_target = kind == 'BRANCH' || (kind == 'JUMP' && rs1.nil?)
      return [nil, 'conflict'] if fixed_target && target != previous[:target]
    end
    instruction[:next_pc] = outcome == 'T' ? target : pc + 4
    [instruction, nil]
  end

  def validate_trace(lines)
    @line_count = lines.length
    @instructions, @rejected, @gaps, @static = [], [], [], {}
    lines.each_with_index do |line, index|
      instruction, error = check_record(line)
      if error
        @rejected << [index + 1, error]
        next
      end
      instruction[:line] = index + 1
      instruction[:number] = @instructions.length + 1
      if !@instructions.empty? && instruction[:pc] != @instructions[-1][:next_pc]
        @gaps << [index + 1, @instructions[-1][:next_pc], instruction[:pc]]
      end
      @instructions << instruction
      @static[instruction[:pc]] ||= instruction
    end
  end

  def predict_trace(definition)
    btb, ras = BTB.new(@config[:btb]), RAS.new(@config[:ras])
    direction = DirectionPredictor.new(definition[:scheme], definition[:parameters])
    details, flags, stats = Array.new(@instructions.length), Array.new(@instructions.length, false), Hash.new(0)
    @instructions.each_with_index do |instruction, index|
      kind = instruction[:class]
      next unless CONTROLS.include?(kind)
      pc, target = instruction.values_at(:pc, :target)
      taken = instruction[:outcome] == 'T'
      candidate = btb.lookup(pc)
      stats['lookups'] += 1
      stats['hits'] += 1 unless candidate.nil?
      is_return = kind == 'JUMP' && instruction[:rd].nil? && instruction[:rs1] == 31
      is_call = kind == 'JUMP' && instruction[:rd] == 31
      stats['calls'] += 1 if is_call
      stats['returns'] += 1 if is_return
      if is_return && !(address = ras.pop).nil?
        candidate = address
        stats['ras_predictions'] += 1
        stats['ras_correct'] += 1 if address == target
      end
      ras.push(pc + 4) if is_call
      predicted_taken = kind == 'BRANCH' ? direction.prediction(pc, target) : true
      predicted_pc = if definition[:scheme] == 'PERFECT'
                       instruction[:next_pc]
                     elsif kind == 'JUMP' || predicted_taken
                       candidate.nil? ? pc + 4 : candidate
                     else pc + 4
                     end
      missed = predicted_pc != instruction[:next_pc]
      miss_kind = nil
      if missed
        miss_kind = if kind == 'BRANCH' && predicted_taken != taken then 'direction'
                    elsif candidate.nil? then 'btb_miss'
                    else 'wrong_target'
                    end
        stats[miss_kind] += 1
      end
      flags[index] = missed
      details[index] = { predicted: predicted_pc, kind: miss_kind, missed: missed }
      stats['control'] += 1
      stats['mispredictions'] += 1 if missed
      stats[kind] += 1
      stats[kind + '_misses'] += 1 if missed
      direction.update(pc, taken) if kind == 'BRANCH'
      btb.insert(pc, target) if taken
    end
    { definition: definition, details: details, flags: flags, statistics: stats, bits: direction.storage_bits }
  end

  def stall_totals(records)
    cycles, events = Hash.new(0), Hash.new(0)
    records.each do |record|
      cycles[record[:cause]] += record[:cycles]
      events[record[:cause]] += 1
    end
    [cycles, events]
  end

  def all_combinations
    @combinations = []
    @config[:variants].each do |variant|
      @config[:predictors].each do |predictor|
        result = simulate(@instructions, @sources, variant, @predictions[predictor[:name]][:flags])
        cycles, events = stall_totals(result[:records])
        @combinations << { variant: variant[:name], predictor: predictor[:name], cycles: result[:cycles], stalls: cycles }
        if [variant[:name], predictor[:name]] == @config[:primary]
          @primary = result.merge(variant: variant, predictor: predictor[:name], stalls: cycles, stall_events: events)
        end
      end
    end
    @combinations.sort_by! { |pair| pair.values_at(:cycles, :variant, :predictor) }
  end

  def dataflow_height
    finish = []
    @instructions.each_with_index do |instruction, index|
      start = @sources[index].filter_map { |s| finish[s[:producer]] unless s[:producer].nil? }.max || 0
      latency = case instruction[:class]
                when 'LOAD' then 2
                when 'MUL' then @primary[:variant][:latency]
                else 1
                end
      finish << start + latency
    end
    finish.max
  end

  def whatif_runs
    variant = @primary[:variant]
    flags = @predictions[@primary[:predictor]][:flags]
    stage = variant[:stage] == 'EX' ? 'ID' : 'EX'
    changes = [
      ['perfect_prediction', variant, Array.new(@instructions.length, false)],
      ['single_cycle_mul', variant.merge(latency: 1), flags],
      [variant[:forwarding] ? 'forwarding_off' : 'forwarding_on', variant.merge(forwarding: !variant[:forwarding]), flags],
      ["branch_stage_#{stage}", variant.merge(stage: stage), flags]
    ]
    changes.map { |name, modified, misses| [name, simulate(@instructions, @sources, modified, misses)[:cycles]] }
  end

  def stall_aggregates
    @class_stalls = Hash.new(0)
    @by_pc = Hash.new { |hash, key| hash[key] = Hash.new(0) }
    @pairs = Hash.new { |hash, key| hash[key] = { cycles: 0, events: 0 } }
    @primary[:records].each do |record|
      instruction = @instructions[record[:responsible]]
      cause, cycles = record.values_at(:cause, :cycles)
      @class_stalls[instruction[:class]] += cycles
      @by_pc[instruction[:pc]][cause] += cycles
      next unless %w[load_use raw].include?(cause)
      key = [@instructions[record[:producer]][:pc], @instructions[record[:waiting]][:pc], cause]
      @pairs[key][:cycles] += cycles
      @pairs[key][:events] += 1
    end
  end

  def forwarding_counts
    counts = Hash.new(0)
    @instructions.each_with_index do |instruction, index|
      @sources[index].each do |source|
        producer = source[:producer]
        producer_time = producer.nil? ? nil : @primary[:timings][producer]
        path = forwarding_path(instruction, producer_time, @primary[:timings][index], @primary[:variant])
        counts[path] += 1
      end
    end
    counts
  end

  def correct_row(instruction, timing, annotation)
    f, d, x, m, w = timing.values_at(:F, :D, :X, :M, :W)
    { number: instruction[:number], pc: instruction[:pc], class: instruction[:class], annotation: annotation,
      characters: [[f, f, 'F'], [f + 1, d - 1, '*'], [d, d, 'D'], [d + 1, x - 1, '*'],
                   [x, m - 1, 'X'], [m, m, 'M'], [w, w, 'W']],
      stages: [['IF', f, d - 1], ['ID', d, x - 1], ['EX', x, m - 1], ['MEM', m, m], ['WB', w, w]] }
  end

  def wrong_rows(prediction, timing, resolved)
    d, x = timing.values_at(:D, :X)
    cancel = resolved ? x : x + 1
    first = { number: nil, pc: prediction[:predicted], class: 'FLUSH', annotation: '',
              characters: [[d, d, 'F'], [d + 1, x - 1, '*'], [cancel, cancel, 'x']], stages: [['IF', d, x - 1]] }
    return [first] if resolved
    first[:characters] << [x, x, 'D']
    first[:stages] << ['ID', x, x]
    second = { number: nil, pc: prediction[:predicted] + 4, class: 'FLUSH', annotation: '',
               characters: [[x, x, 'F'], [x + 1, x + 1, 'x']], stages: [['IF', x, x]] }
    [first, second]
  end

  def build_rows
    annotations = Hash.new { |hash, key| hash[key] = [] }
    @primary[:records].each do |record|
      annotations[record[:waiting]] << " #{record[:cause]} #{record[:cycles]}" unless record[:waiting].nil?
    end
    @rows = []
    prediction = @predictions[@primary[:predictor]]
    @instructions.zip(@primary[:timings]).each_with_index do |(instruction, timing), index|
      annotation = annotations[index].join
      detail = prediction[:details][index]
      annotation += " mispredict #{detail[:kind]}" if prediction[:flags][index]
      @rows << correct_row(instruction, timing, annotation)
      @rows.concat(wrong_rows(detail, timing, id_resolved(instruction, @primary[:variant]))) if prediction[:flags][index]
    end
  end

  def occupancy
    counts = STAGES.to_h { |stage| [stage, Hash.new(0)] }
    @rows.each do |row|
      kind = row[:number].nil? ? :wrong : :correct
      row[:stages].each { |stage, first, last| counts[stage][kind] += last - first + 1 }
    end
    counts
  end

  def pipeline_lines
    first, last = @config[:window]
    width = last - first + 1
    lines = ["pipeline variant=#{@primary[:variant][:name]} predictor=#{@primary[:predictor]} cycles #{first}-#{last}", cycle_heading(first, last)]
    contents = Array.new(width) { Array.new(STAGES.length, '.') }
    visible = stalled = flushed = 0
    @rows.each do |row|
      characters = Array.new(width, '.')
      row[:characters].each do |start, finish, symbol|
        ([first, start].max..[last, finish].min).each { |cycle| characters[cycle - first] = symbol }
      end
      if characters.any? { |symbol| symbol != '.' }
        visible += 1
        stalled += characters.count('*')
        flushed += characters.count('x')
        lines << diagram_row(row[:number], row[:pc], row[:class], characters.join, row[:annotation])
      end
      row[:stages].each do |stage, start, finish|
        ([first, start].max..[last, finish].min).each do |cycle|
          contents[cycle - first][STAGES.index(stage)] = row[:number].nil? ? 'w' : row[:number].to_s
        end
      end
    end
    completed = @primary[:timings].count { |time| time[:W].between?(first, last) }
    lines.concat(["rows #{visible} completed #{completed} stall_cells #{stalled} flushed #{flushed}", '', 'stages', 'cycle IF ID EX MEM WB'])
    contents.each_with_index { |content, i| lines << "#{first + i} #{content.join(' ')}" }
    lines
  end

  def input_part
    lines = ["input lines #{@line_count} accepted #{@instructions.length} rejected #{@rejected.length} gaps #{@gaps.length}"]
    @rejected.each { |line, reason| lines << "reject line #{line} #{reason}" }
    @gaps.each { |line, expected, found| lines << "gap line #{line} expected #{hexadecimal(expected)} found #{hexadecimal(found)}" }
    lines
  end

  def trace_part
    classes = @instructions.map { |i| i[:class] }.tally
    classes.default = 0
    branches = @instructions.select { |i| i[:class] == 'BRANCH' }
    jumps = @instructions.select { |i| i[:class] == 'JUMP' }
    addresses = @instructions.select { |i| %w[LOAD STORE].include?(i[:class]) }.map { |i| i[:address] }.uniq
    distances = Hash.new(0)
    @sources.each_with_index do |operands, index|
      operands.each { |source| distances[[5, index - source[:producer]].min] += 1 unless source[:producer].nil? }
    end
    ['trace', "instructions #{@instructions.length}", "static_instructions #{@static.length}",
     'mix ' + CLASSES.map { |kind| "#{kind} #{classes[kind]}" }.join(' '),
     "branches #{branches.length} taken #{branches.count { |i| i[:outcome] == 'T' }} backward #{branches.count { |i| i[:target] < i[:pc] }}",
     "jumps #{jumps.length} indirect #{jumps.count { |i| !i[:rs1].nil? }} link #{jumps.count { |i| !i[:rd].nil? }}",
     "static_control branches #{@static.values.count { |i| i[:class] == 'BRANCH' }} jumps #{@static.values.count { |i| i[:class] == 'JUMP' }}",
     "memory loads #{classes['LOAD']} stores #{classes['STORE']} distinct_addresses #{addresses.length}",
     "operands #{@sources.sum(&:length)} with_producer #{distances.values.sum} distance " +
       %w[1 2 3 4 5+].each_with_index.map { |label, i| "#{label} #{distances[i + 1]}" }.join(' ')]
  end

  def prediction_accuracy(prediction, kind = 'control')
    stats = prediction[:statistics]
    misses = stats[kind == 'control' ? 'mispredictions' : kind + '_misses']
    percentage(stats[kind] - misses, stats[kind])
  end

  def prediction_part
    lines = ['prediction']
    @config[:predictors].each do |definition|
      prediction = @predictions[definition[:name]]
      stats = prediction[:statistics]
      lines << "#{definition[:name]} #{definition[:scheme]} bits #{prediction[:bits]} control #{stats['control']} mispredicted #{stats['mispredictions']} accuracy #{prediction_accuracy(prediction)} branches #{prediction_accuracy(prediction, 'BRANCH')} jumps #{prediction_accuracy(prediction, 'JUMP')} " +
        MISS_KINDS.map { |kind| "#{kind} #{stats[kind]}" }.join(' ')
    end
    stats = @predictions[@config[:predictors][0][:name]][:statistics]
    lines << "btb entries #{@config[:btb]} lookups #{stats['lookups']} hits #{stats['hits']} misses #{stats['lookups'] - stats['hits']}"
    lines << "ras depth #{@config[:ras]} calls #{stats['calls']} returns #{stats['returns']} predicted #{stats['ras_predictions']} correct #{stats['ras_correct']}"
    lines
  end

  def cause_values(values) = CAUSES.map { |cause| "#{cause} #{values[cause]}" }.join(' ')

  def timing_part
    variant, cycles, stalls = @primary.values_at(:variant, :cycles, :stalls)
    n = @instructions.length
    total = stalls.values.sum
    lengths = Hash.new(0)
    @primary[:delays].each { |delay| lengths[[5, delay].min] += 1 if delay.positive? }
    ["timing variant=#{variant[:name]} predictor=#{@primary[:predictor]}",
     "forwarding #{variant[:forwarding] ? 'on' : 'off'} branch_stage #{variant[:stage]} mul_latency #{variant[:latency]}",
     "cycles #{cycles}", "cpi #{reduced_fraction(cycles, n)} #{decimal(cycles, n)}", "ipc #{decimal(n, cycles)}",
     "stall_cycles total #{total} #{cause_values(stalls)}", "stall_events #{cause_values(@primary[:stall_events])}",
     "flushed #{@rows.count { |row| row[:number].nil? }}", "cycle_check #{n} + 4 + #{total} = #{n + 4 + total}",
     "cpi_stack base 1.0000 fill #{decimal(4, n)} " + CAUSES.map { |cause| "#{cause} #{decimal(stalls[cause], n)}" }.join(' '),
     'stall_lengths ' + %w[1 2 3 4 5+].each_with_index.map { |label, i| "#{label} #{lengths[i + 1]}" }.join(' '),
     "dataflow height #{dataflow_height} ilp #{decimal(n, dataflow_height)}"]
  end

  def whatif_part
    ['whatif'] + (whatif_runs.map do |name, cycles|
      "#{name} cycles #{cycles} saved #{@primary[:cycles] - cycles} speedup #{decimal(@primary[:cycles], cycles)}"
    end)
  end

  def classes_part
    counts = @instructions.map { |i| i[:class] }.tally
    counts.default = 0
    ['classes'] + (CLASSES.map do |kind|
      per_instruction = counts[kind].zero? ? '-' : decimal(@class_stalls[kind], counts[kind])
      "#{kind} count #{counts[kind]} stall_cycles #{@class_stalls[kind]} per_instruction #{per_instruction}"
    end)
  end

  def occupancy_part
    counts = occupancy
    cycles = @primary[:cycles]
    ["occupancy cycles #{cycles}"] + (STAGES.map do |stage|
      correct, wrong = counts[stage][:correct], counts[stage][:wrong]
      "#{stage} correct #{correct} wrong #{wrong} idle #{cycles - correct - wrong} busy #{percentage(correct + wrong, cycles)}"
    end)
  end

  def hotspots_part
    pcs = @by_pc.keys.select { |pc| @by_pc[pc].values.sum.positive? }.sort_by { |pc| [-@by_pc[pc].values.sum, pc] }.take(@config[:top])
    ['hotspots'] + (pcs.each_with_index.map do |pc, index|
      causes = @by_pc[pc]
      "#{index + 1} #{hexadecimal(pc)} #{@static[pc][:class]} stall_cycles #{causes.values.sum} #{cause_values(causes)}"
    end)
  end

  def dependencies_part
    keys = @pairs.keys.sort_by { |key| [-@pairs[key][:cycles], key[0], key[1], CAUSES.index(key[2])] }
    ["dependencies total #{@pairs.length}"] + (keys.take(@config[:top]).each_with_index.map do |key, index|
      producer, waiting, cause = key
      data = @pairs[key]
      "#{index + 1} #{hexadecimal(producer)} #{@static[producer][:class]} -> #{hexadecimal(waiting)} #{@static[waiting][:class]} #{cause} stall_cycles #{data[:cycles]} events #{data[:events]}"
    end)
  end

  def intervals_part
    size, timings = @config[:interval], @primary[:timings]
    lines = ["intervals size #{size}"]
    (0...timings.length).step(size) do |first|
      last = [timings.length, first + size].min - 1
      previous = first.zero? ? 0 : timings[first - 1][:W]
      cycles = timings[last][:W] - previous
      lines << "#{first + 1}-#{last + 1} cycles #{cycles} cpi #{decimal(cycles, last - first + 1)}"
    end
    lines
  end

  def cycles_table_part
    table = @combinations.to_h { |pair| [[pair[:variant], pair[:predictor]], pair[:cycles]] }
    names = @config[:predictors].map { |definition| definition[:name] }
    ["cycles_table #{names.join(' ')}"] + (@config[:variants].map do |variant|
      variant[:name] + ' ' + names.map { |name| table[[variant[:name], name]] }.join(' ')
    end)
  end

  def statistics_lines
    forwarding = forwarding_counts
    forward_line = 'forwarding ' + %w[regfile ex_mem mem_wb].map { |path| "#{path} #{forwarding[path]}" }.join(' ')
    join_parts([input_part, trace_part, prediction_part, timing_part, whatif_part, classes_part,
                [forward_line], occupancy_part, hotspots_part, dependencies_part, intervals_part, cycles_table_part])
  end

  def branch_lines
    lines = ['predictor,pc,class,executions,taken,mispredictions,accuracy']
    @config[:predictors].each do |definition|
      name = definition[:name]
      flags = @predictions[name][:flags]
      @groups.each do |pc, indices|
        kind = @instructions[indices[0]][:class]
        next unless CONTROLS.include?(kind)
        taken = indices.count { |i| @instructions[i][:outcome] == 'T' }
        missed = indices.count { |i| flags[i] }
        lines << [name, hexadecimal(pc), kind, indices.length, taken, missed, percentage(indices.length - missed, indices.length)].join(',')
      end
    end
    lines
  end

  def comparison_lines
    lines = ['rank,variant,predictor,cycles,cpi,speedup,accuracy,mispredictions,control,structural,load_use,raw']
    @combinations.each_with_index do |pair, index|
      prediction = @predictions[pair[:predictor]]
      values = [index + 1, pair[:variant], pair[:predictor], pair[:cycles], decimal(pair[:cycles], @instructions.length),
                decimal(@primary[:cycles], pair[:cycles]), prediction_accuracy(prediction), prediction[:statistics]['mispredictions']]
      values.concat(CAUSES.map { |cause| pair[:stalls][cause] })
      lines << values.join(',')
    end
    lines
  end

  def branch_profile
    lines = ['branches']
    choices = @config[:predictors].reject { |definition| definition[:scheme] == 'PERFECT' }.map { |definition| definition[:name] }
    @groups.each do |pc, indices|
      instruction = @instructions[indices[0]]
      next unless instruction[:class] == 'BRANCH'
      outcomes = indices.map { |i| @instructions[i][:outcome] }
      transitions = outcomes.each_cons(2).count { |a, b| a != b }
      longest = { 'T' => 0, 'N' => 0 }
      previous, length = nil, 0
      outcomes.each do |outcome|
        length = outcome == previous ? length + 1 : 1
        longest[outcome] = [longest[outcome], length].max
        previous = outcome
      end
      misses = choices.to_h { |name| [name, indices.count { |i| @predictions[name][:flags][i] }] }
      best = choices.each_with_index.min_by { |name, order| [misses[name], order] }[0]
      direction = instruction[:target] < pc ? 'backward' : 'forward'
      lines << "#{hexadecimal(pc)} #{direction} executions #{indices.length} taken #{outcomes.count('T')} transitions #{transitions} longest_taken #{longest['T']} longest_not_taken #{longest['N']} best #{best} #{misses[best]}"
    end
    lines
  end

  def loops_profile
    lines = ['loops']
    @groups.each do |pc, indices|
      instruction = @instructions[indices[0]]
      next unless instruction[:class] == 'BRANCH' && instruction[:target] < pc
      trips, length = [], 0
      indices.each do |index|
        length += 1
        if @instructions[index][:outcome] == 'N'
          trips << length
          length = 0
        end
      end
      trips << length if length.positive?
      target = instruction[:target]
      lines << "#{hexadecimal(target)}-#{hexadecimal(pc)} body #{(pc - target).div(4) + 1} entries #{trips.length} iterations #{indices.length} avg_trip #{decimal(indices.length, trips.length)} max_trip #{trips.max}"
    end
    lines
  end

  def segments_profile
    groups = Hash.new { |hash, key| hash[key] = { instances: 0, instructions: 0, cycles: 0 } }
    first = 0
    timings = @primary[:timings]
    @instructions.each_with_index do |instruction, last|
      next unless CONTROLS.include?(instruction[:class]) || last == @instructions.length - 1
      group = groups[@instructions[first][:pc]]
      group[:instances] += 1
      group[:instructions] += last - first + 1
      group[:cycles] += timings[last][:W] - (first.zero? ? 0 : timings[first - 1][:W])
      first = last + 1
    end
    ranked = groups.keys.sort_by { |pc| [-groups[pc][:cycles], pc] }.take(@config[:top])
    ["segments total #{groups.length}"] + (ranked.each_with_index.map do |pc, index|
      group = groups[pc]
      "#{index + 1} #{hexadecimal(pc)} instances #{group[:instances]} instructions #{group[:instructions]} cycles #{group[:cycles]} cpi #{decimal(group[:cycles], group[:instructions])}"
    end)
  end

  def indirect_profile
    lines = ['indirect']
    @groups.each do |pc, indices|
      instruction = @instructions[indices[0]]
      next unless instruction[:class] == 'JUMP' && !instruction[:rs1].nil?
      targets = indices.map { |i| @instructions[i][:target] }.tally
      values = targets.keys.sort_by { |target| [-targets[target], target] }.map { |target| "#{hexadecimal(target)}:#{targets[target]}" }.join(' ')
      lines << "#{hexadecimal(pc)} executions #{indices.length} distinct #{targets.length} targets #{values}"
    end
    lines
  end

  def static_profile
    ['instructions'] + (@groups.map do |pc, indices|
      instruction = @instructions[indices[0]]
      operands = %i[rd rs1 rs2].map { |key| register(instruction[key]) }.join(' ')
      "#{hexadecimal(pc)} #{instruction[:class]} #{operands} executions #{indices.length} stall_cycles #{@by_pc[pc].values.sum}"
    end)
  end

  def run
    lines, @config = read_inputs
    validate_trace(lines)
    @sources = dependencies(@instructions)
    @predictions = @config[:predictors].to_h { |definition| [definition[:name], predict_trace(definition)] }
    all_combinations
    stall_aggregates
    build_rows
    @groups = Hash.new { |hash, key| hash[key] = [] }
    @instructions.each_with_index { |instruction, index| @groups[instruction[:pc]] << index }
    @groups = @groups.sort.to_h
    write_lines('pipeline.txt', pipeline_lines)
    write_lines('stats.txt', statistics_lines)
    write_lines('branches.csv', branch_lines)
    write_lines('comparison.csv', comparison_lines)
    write_lines('profile.txt', join_parts([branch_profile, loops_profile, segments_profile, indirect_profile, static_profile]))
  end
end

CpuSimulation.new.run if $PROGRAM_NAME == __FILE__
