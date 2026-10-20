require_relative 'dataflow'
require_relative 'optimizations'
require_relative 'regalloc'

module TAC
  class Optimizer
    PASSES = %i[constprop copyprop cse dce licm unreachable].freeze
    def list(values) = values.empty? ? '-' : values.join(',')
    def analyses(function)
      cfg = CFG.new(function)
      [cfg, Dataflow.new(function, cfg)]
    end
    def propagate(function, cfg, flow, mode)
      snapshot = function.instructions.to_h { |s| [s.number, s.dup] }
      records, replacements = [], {}
      cfg.reachable.each do |b|
        b.instructions.each do |s|
          s.operand_fields.each do |field|
            v = s.public_send(field)
            next unless v.is_a?(String)
            value = nil
            if mode == :constprop
              definitions = flow.before[:rd][s.number].select { |x, _| x == v }
              constants = definitions.map do |_, n|
                d = snapshot[n]
                d && d.kind == :copy && d.a.is_a?(Integer) ? d.a : nil
              end
              value = constants.first if !constants.empty? && constants.none?(&:nil?) && constants.uniq.length == 1
            else
              pair = flow.before[:copies][s.number].find { |x, _| x == v }
              value = pair[1] if pair
            end
            next if value.nil?
            s.public_send("#{field}=", value)
            records << "##{s.number}: #{v} -> #{value}"
          end
          next unless mode == :constprop
          result, record = Rewriting.fold(s)
          if record
            records << "##{s.number}: #{record}"
            replacements[s.object_id] = result ? [result] : []
          end
        end
      end
      Rewriting.replace(function, replacements)
      [records.length, records]
    end
    def common_subexpressions(function, cfg, flow)
      groups = {}
      cfg.reachable.each do |b|
        b.instructions.each do |s|
          e = s.expression
          (groups[e] ||= []) << s if e && flow.before[:expr][s.number].include?(e)
        end
      end
      records, count = [], 0
      groups.values.sort_by { |c| c.first.number }.each do |candidates|
        e = candidates.first.expression
        sources = Set.new
        candidates.each do |s|
          b = cfg.owner.fetch(s.number)
          local = b.instructions.take_while { |i| i.number != s.number }.reverse.find { |i| i.expression == e }
          if local
            sources << local.number
            next
          end
          searched, work = Set.new, b.preds.select { |p| flow.input[:expr].key?(p.id) }
          until work.empty?
            p = work.pop
            next unless searched.add?(p.id)
            last = p.instructions.reverse.find { |i| i.expression == e }
            if last
              sources << last.number
            else
              work.concat(p.preds.select { |q| flow.input[:expr].key?(q.id) })
            end
          end
        end
        sources.subtract(candidates.map(&:number))
        source_instructions = sources.sort.map { |n| cfg.owner[n].instructions.find { |s| s.number == n } }
        name = Rewriting.cse(function, e, source_instructions, candidates)
        records << "#{TAC.expression_text(e)}: #{name} sources=#{list(sources.sort.map { |n| "##{n}" })} replaced=#{list(candidates.map { |s| "##{s.number}" })}"
        count += candidates.length
      end
      [count, records]
    end
    def dead_code(function, cfg, flow)
      records, replacements = [], {}
      cfg.reachable.each do |b|
        live = flow.output[:live][b.id].dup
        b.instructions.reverse_each do |s|
          if s.kind == :copy && s.x == s.a || %i[copy bin load].include?(s.kind) && !live.include?(s.x)
            records << [s.number, "##{s.number}: delete #{s}"]
            replacements[s.object_id] = []
            next
          end
          if s.kind == :call && s.x && !live.include?(s.x)
            records << [s.number, "##{s.number}: unused result #{s}"]
            s.x = nil
          end
          live.delete(s.x)
          live.merge(s.uses)
        end
      end
      Rewriting.replace(function, replacements)
      [records.length, records.sort_by(&:first).map(&:last)]
    end
    def invariant_motion(function, cfg, flow)
      cfg.loops.sort_by { |l| [l.blocks.length, l.header.id] }.each do |l|
        instructions = l.blocks.flat_map(&:instructions).sort_by(&:number)
        internal = instructions.map(&:number).to_set
        marked, order = Set.new, []
        loop do
          changed = false
          instructions.each do |s|
            next if marked.include?(s.number) || !%i[copy bin load].include?(s.kind)
            next if s.kind == :load && instructions.any? { |v| v.kind == :call || v.kind == :store && v.array == s.array }
            valid = s.uses.all? do |v|
              ds = flow.before[:rd][s.number].select { |x, _| x == v }.map(&:last)
              ds.none? { |n| internal.include?(n) } || ds.length == 1 && marked.include?(ds.first)
            end
            next unless valid
            marked << s.number
            order << s
            changed = true
          end
          break unless changed
        end
        moving = []
        order.each do |s|
          next unless instructions.count { |v| v.x == s.x } == 1
          next if flow.input[:live][l.header.id].include?(s.x)
          h = cfg.owner[s.number]
          dominates = l.exits.all? { |v| v.dom.include?(h.id) }
          dangerous = s.kind == :load || s.kind == :bin && %w[/ %].include?(s.op) && (s.b.is_a?(String) || s.b == 0)
          safe = !dangerous && l.outside.none? { |v| flow.input[:live][v.id].include?(s.x) }
          next unless dominates || safe
          moved = moving.map(&:number).to_set
          next unless s.uses.all? do |v|
            flow.before[:rd][s.number].select { |x, n| x == v && internal.include?(n) }.all? { |_, n| moved.include?(n) }
          end
          moving << s
        end
        next if moving.empty?
        destination = Rewriting.hoist(function, l, moving)
        return [moving.length, ["#{l.header}: hoist #{moving.map { |s| "##{s.number}" }.join(',')} to #{destination}"]]
      end
      [0, []]
    end
    def optimize(function, enabled, max_rounds, totals)
      lines = ["== #{function.name} =="]
      initial = function.instructions.length
      rounds = 0
      max_rounds.times do |index|
        rounds = index + 1
        counts, records = [], []
        enabled.each do |name|
          cfg, flow = analyses(function)
          count, entries = case name
                           when :constprop, :copyprop then propagate(function, cfg, flow, name)
                           when :cse then common_subexpressions(function, cfg, flow)
                           when :dce then dead_code(function, cfg, flow)
                           when :licm then invariant_motion(function, cfg, flow)
                           when :unreachable then r = Rewriting.unreachable(function, cfg); [r.length, r]
                           end
          totals[name] += count
          counts << [name, count]
          records.concat(entries.map { |r| "  #{name} #{r}" })
        end
        lines << "round #{rounds}: #{counts.map { |n, c| "#{n}=#{c}" }.join(' ')}"
        lines.concat(records)
        break if counts.all? { |_, c| c.zero? }
      end
      lines << "result: rounds=#{rounds} instructions=#{initial}->#{function.instructions.length}"
      lines
    end
    def call_graph(program)
      names = program.functions.map(&:name)
      graph = program.functions.to_h { |f| [f.name, names & f.instructions.select { |s| s.kind == :call }.map(&:callee)] }
      reachable = lambda do |start|
        seen, work = Set.new, graph.fetch(start).dup
        until work.empty?
          f = work.pop
          work.concat(graph.fetch(f)) if seen.add?(f)
        end
        seen
      end
      main = reachable.call('main') | Set['main']
      removed = names.reject { |f| main.include?(f) }
      lines = names.map { |f| "#{f} -> #{list(graph[f])}#{reachable.call(f).include?(f) ? ' (recursive)' : ''}" }
      [lines + ["unreachable functions: #{list(removed)}"], removed]
    end
    def function_analysis(function, type)
      cfg, flow = analyses(function)
      lines = ["== #{function.name} (#{type}) ==", 'code:']
      function.code.each do |s|
        if s.is_a?(String)
          lines << "#{s}:"
        else
          text = "  ##{s.number} #{s}"
          if flow.before[:rd].key?(s.number) && !s.uses.empty?
            ud = s.uses.uniq.map do |v|
              numbers = flow.before[:rd][s.number].select { |x, _| x == v }.map(&:last).sort
              "#{v}:#{numbers.join(',')}"
            end
            text += " | #{ud.join(' ')}"
          end
          lines << text
        end
      end
      lines << "blocks: #{cfg.blocks.length}"
      cfg.blocks.each do |b|
        lines << "#{b} #{b.instructions.first.number}-#{b.instructions.last.number} labels=#{list(b.labels)} preds=#{list(b.preds)} succs=#{list(b.succs)}"
      end
      lines << "unreachable: #{list(cfg.blocks - cfg.reachable)}"
      lines << "order: #{list(cfg.order)}"
      lines << 'dominators:'
      cfg.reachable.each { |b| lines << "#{b} idom=#{b.idom || '-'} dom=#{list(b.dom.to_a.sort.map { |n| "B#{n}" })}" }
      lines << 'dominator tree:'
      tree = lambda do |b, depth|
        lines << "#{'  ' * depth}#{b}"
        cfg.reachable.select { |v| v.idom == b }.each { |v| tree.call(v, depth + 1) }
      end
      tree.call(cfg.blocks.first, 0)
      lines << "loops: #{cfg.loops.length}"
      cfg.loops.each do |l|
        lines << "header=#{l.header} latches=#{list(l.latches)} depth=#{l.depth} blocks=#{list(l.blocks)} exits=#{list(l.exits)}"
      end
      { rd: 'reaching definitions', live: 'liveness', expr: 'available expressions' }.each do |kind, title|
        lines << "#{title}: iterations=#{flow.iterations[kind]}"
        format = lambda do |set|
          values = case kind
                   when :rd then set.sort_by { |v, n| [n, v] }.map { |v, n| "#{v}:#{n}" }
                   when :expr then set.map { |e| TAC.expression_text(e) }.sort
                   else set.to_a.sort
                   end
          list(values)
        end
        cfg.reachable.each { |b| lines << "#{b} in=#{format.call(flow.input[kind][b.id])} out=#{format.call(flow.output[kind][b.id])}" }
      end
      lines
    end
    def allocate(function, k)
      cfg, flow = analyses(function)
      allocation = Allocation.new(function, cfg, flow, k)
      graph, colors = allocation.graph, allocation.colors
      lines = ["== #{function.name} ==", "nodes=#{graph.length} edges=#{graph.values.sum(&:size) / 2} registers=#{k}"]
      graph.each { |v, ns| lines << "#{v} degree=#{ns.size} cost=#{allocation.cost[v]} neighbors=#{list(ns.to_a.sort)}" }
      lines << "simplify: #{list(allocation.order)}"
      lines << "potential spills: #{list(allocation.potential.map { |v, c, d| "#{v}(#{c}/#{d})" })}"
      graph.each_key { |v| lines << "#{v} -> #{colors[v].nil? ? 'spill' : "R#{colors[v]}"}" }
      pressure = cfg.reachable.flat_map(&:instructions).flat_map { |s| [flow.before[:live][s.number].size, flow.after[:live][s.number].size] }.max || 0
      spilled = colors.select { |_, c| c.nil? }.keys.to_set
      uses = function.instructions.sum { |s| s.uses.count { |v| spilled.include?(v) } }
      defs = function.instructions.count { |s| spilled.include?(s.x) } + function.params.count { |v| spilled.include?(v) }
      rewrite = ->(v) { colors[v].nil? ? v : "R#{colors[v]}" }
      allocated = Marshal.load(Marshal.dump(function))
      allocated.params.map! { |v| rewrite.call(v) }
      allocated.instructions.each do |s|
        s.x = rewrite.call(s.x) if s.x
        s.operand_fields.each { |f| s.public_send("#{f}=", rewrite.call(s.public_send(f))) if s.public_send(f).is_a?(String) }
      end
      moves = allocated.instructions.count { |s| s.kind == :copy && s.x == s.a }
      allocated.code.reject! { |s| s.is_a?(Instruction) && s.kind == :copy && s.x == s.a }
      lines << "summary: pressure=#{pressure} used=#{colors.values.compact.uniq.length} spilled=#{spilled.size} moves=#{moves} spill_uses=#{uses} spill_defs=#{defs}"
      lines.concat(allocated.lines)
      [allocated, lines]
    end
    def execute(program, inputs)
      arrays = program.arrays.to_h { |n, size| [n, Array.new(size, 0)] }
      functions = program.functions.to_h { |f| [f.name, f] }
      steps, calls, kinds, output = Hash.new(0), Hash.new(0), Hash.new(0), []
      position = 0
      invoke = lambda do |name, arguments|
        f = functions.fetch(name)
        calls[name] += 1
        values, pending, code, labels = f.params.zip(arguments).to_h, [], [], {}
        f.code.each { |s| s.is_a?(String) ? labels[s] = code.length : code << s }
        value = ->(v) { v.is_a?(Integer) ? v : values.fetch(v) }
        pc = 0
        while pc < code.length
          s = code[pc]
          steps[name] += 1
          kinds[s.kind] += 1
          pc += 1
          case s.kind
          when :copy then values[s.x] = value.call(s.a)
          when :bin then values[s.x] = TAC.calculate(s.op, value.call(s.a), value.call(s.b))
          when :load then values[s.x] = arrays.fetch(s.array).fetch(value.call(s.a))
          when :store then arrays.fetch(s.array)[value.call(s.a)] = value.call(s.b)
          when :goto then pc = labels.fetch(s.target)
          when :if then pc = labels.fetch(s.target) unless TAC.calculate(s.op, value.call(s.a), value.call(s.b)).zero?
          when :param then pending << value.call(s.a)
          when :call
            args = s.argc.zero? ? [] : pending.pop(s.argc)
            result = invoke.call(s.callee, args)
            values[s.x] = result if s.x
          when :return then return_value = s.a.nil? ? nil : value.call(s.a); break
          when :read then values[s.x] = inputs.fetch(position); position += 1
          when :print then output << value.call(s.a)
          end
        end
        return_value
      end
      invoke.call('main', [])
      { steps: steps, calls: calls, kinds: kinds, output: output }
    end
    def comparisons(programs, runs)
      names = %w[original optimized allocated]
      totals = programs.map { { steps: Hash.new(0), calls: Hash.new(0), kinds: Hash.new(0) } }
      same, lines = 0, []
      runs.each_with_index do |values, i|
        results = programs.map { |p| execute(p, values) }
        lines << "run #{i + 1}: inputs=#{values.length}"
        results.each_with_index do |r, j|
          lines << "  #{names[j]}: steps=#{r[:steps].values.sum} calls=#{r[:calls].values.sum} output=#{list(r[:output])}"
          %i[steps calls kinds].each { |key| r[key].each { |v, n| totals[j][key][v] += n } }
        end
        equal = results.map { |r| r[:output] }.uniq.length == 1
        same += 1 if equal
        lines << "  result: #{equal ? 'same' : 'different'}"
      end
      lines << '== profile =='
      programs.first.functions.each do |f|
        lines << "#{f.name}: calls=#{totals[0][:calls][f.name]} original=#{totals[0][:steps][f.name]} optimized=#{totals[1][:steps][f.name]} allocated=#{totals[2][:steps][f.name]}"
      end
      lines << '== summary =='
      lines << "runs=#{runs.length} same=#{same} different=#{runs.length - same}"
      counts = programs.first(2).map { |p| p.functions.flat_map(&:instructions).group_by(&:kind).transform_values(&:length) }
      lines << "instructions: original=#{counts[0].values.sum} optimized=#{counts[1].values.sum}"
      lines << "kinds: #{KINDS.map { |kind| "#{kind}=#{counts[0].fetch(kind, 0)}->#{counts[1].fetch(kind, 0)}" }.join(' ')}"
      lines << "steps: #{names.each_with_index.map { |n, i| "#{n}=#{totals[i][:steps].values.sum}" }.join(' ')}"
      names.each_with_index { |n, i| lines << "dynamic #{n}: #{KINDS.map { |kind| "#{kind}=#{totals[i][:kinds][kind]}" }.join(' ')}" }
      lines
    end
    def run
      settings = File.readlines('input/params.txt', chomp: true).map(&:split)
      k, rounds = settings[0][1].to_i, settings[2][1].to_i
      enabled = PASSES & settings[1].drop(1).map(&:to_sym)
      runs = File.readlines('input/input.txt', chomp: true).drop(1).map { |line| line.split.drop(1).map(&:to_i) }
      original = TAC.parse('input/program.tac')
      optimized = Marshal.load(Marshal.dump(original))
      graph_lines, = call_graph(original)
      analysis = ['== call graph (original) ==', *graph_lines]
      original.functions.each { |f| analysis.concat(function_analysis(f, 'original')) }
      totals, passes = Hash.new(0), []
      optimized.functions.each { |f| passes.concat(optimize(f, enabled, rounds, totals)) }
      graph_lines, removed = call_graph(optimized)
      analysis.concat(['== call graph (optimized) ==', *graph_lines])
      removed = [] unless enabled.include?(:unreachable)
      optimized.functions.reject! { |f| removed.include?(f.name) }
      optimized.functions.each { |f| analysis.concat(function_analysis(f, 'optimized')) }
      passes.concat(['== program ==', "removed functions: #{list(removed)}", '== total ==', enabled.map { |n| "#{n}=#{totals[n]}" }.join(' ')])
      allocated_functions, allocation_lines = [], []
      optimized.functions.each do |f|
        allocated, lines = allocate(f, k)
        allocated_functions << allocated
        allocation_lines.concat(lines)
      end
      allocated = Program.new(optimized.arrays, allocated_functions)
      File.write('output/optimized.tac', optimized.to_s)
      { 'analysis' => analysis, 'passes' => passes, 'regalloc' => allocation_lines,
        'comparison' => comparisons([original, optimized, allocated], runs) }.each do |name, lines|
        File.write("output/#{name}.txt", lines.join("\n") + "\n")
      end
    end
  end
end

TAC::Optimizer.new.run if $PROGRAM_NAME == __FILE__
