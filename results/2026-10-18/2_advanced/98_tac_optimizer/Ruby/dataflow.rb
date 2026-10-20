require_relative 'cfg'

module TAC
  class Dataflow
    attr_reader :cfg, :input, :output, :iterations, :before, :after
    def initialize(function, cfg)
      @cfg, @input, @output, @iterations, @before, @after = cfg, {}, {}, {}, {}, {}
      instructions = cfg.reachable.flat_map(&:instructions)
      universes = { rd: Set.new, live: Set.new, expr: instructions.filter_map(&:expression).to_set,
                    copies: instructions.select { |s| s.kind == :copy && s.a.is_a?(String) && s.a != s.x }.map { |s| [s.x, s.a] }.to_set }
      universes.each do |kind, universe|
        ins, outs = {}, {}
        cfg.reachable.each { |b| ins[b.id] = Set.new; outs[b.id] = %i[expr copies].include?(kind) ? universe.dup : Set.new }
        count = 0
        loop do
          count += 1
          changed = false
          (kind == :live ? cfg.postorder : cfg.order).each do |b|
            if kind == :live
              outs[b.id] = b.succs.map { |v| ins[v.id] }.reduce(Set.new, :|)
              value = b.instructions.reverse.reduce(outs[b.id]) { |set, s| transfer(kind, set, s) }
              changed = true if value != ins[b.id]
              ins[b.id] = value
            else
              preds = b.preds.select { |p| outs.key?(p.id) }.map { |p| outs[p.id] }
              ins[b.id] = if kind == :rd
                            preds.reduce(Set.new, :|) | (b.id == 1 ? function.params.map { |p| [p, 0] }.to_set : Set.new)
                          elsif b.id == 1
                            Set.new
                          else
                            preds.reduce { |a, v| a & v } || Set.new
                          end
              value = b.instructions.reduce(ins[b.id]) { |set, s| transfer(kind, set, s) }
              changed = true if value != outs[b.id]
              outs[b.id] = value
            end
          end
          break unless changed
        end
        input[kind], output[kind], iterations[kind] = ins, outs, count
        before[kind], after[kind] = {}, {}
        cfg.reachable.each do |b|
          state = kind == :live ? outs[b.id] : ins[b.id]
          (kind == :live ? b.instructions.reverse : b.instructions).each do |s|
            (kind == :live ? after : before)[kind][s.number] = state
            state = transfer(kind, state, s)
            (kind == :live ? before : after)[kind][s.number] = state
          end
        end
      end
    end
    def transfer(kind, state, s)
      set = state.dup
      case kind
      when :rd
        if s.x
          set.delete_if { |v, _| v == s.x }
          set << [s.x, s.number]
        end
      when :live
        set.delete(s.x)
        set.merge(s.uses)
      when :copies
        set.delete_if { |x, y| x == s.x || y == s.x } if s.x
        set << [s.x, s.a] if s.kind == :copy && s.a.is_a?(String) && s.a != s.x
      when :expr
        set << s.expression if s.expression
        set.delete_if { |e| e[0] == :load && e[1] == s.array } if s.kind == :store
        set.delete_if { |e| e[0] == :load } if s.kind == :call
        set.delete_if { |e| e.drop(2).include?(s.x) } if s.x
      end
      set
    end
  end
end
