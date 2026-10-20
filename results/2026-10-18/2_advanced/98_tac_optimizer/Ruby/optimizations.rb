require_relative 'tac_parser'

module TAC
  module Rewriting
    def self.fold(s)
      if s.kind == :if && s.a.is_a?(Integer) && s.b.is_a?(Integer)
        return [nil, "delete #{s}"] if TAC.calculate(s.op, s.a, s.b).zero?
        r = Instruction.new(kind: :goto, target: s.target)
        return [r, "fold #{r}"]
      end
      return [s, nil] unless s.kind == :bin
      value = nil
      if s.a.is_a?(Integer) && s.b.is_a?(Integer)
        return [s, nil] if %w[/ %].include?(s.op) && s.b.zero?
        value = TAC.calculate(s.op, s.a, s.b)
        return [s, nil] unless (-2147483648..2147483647).cover?(value)
      elsif s.a.is_a?(Integer) != s.b.is_a?(Integer)
        value = s.b if s.a == 0 && s.op == '+' || s.a == 1 && s.op == '*'
        value = s.a if s.b == 0 && %w[+ -].include?(s.op) || s.b == 1 && %w[* /].include?(s.op)
        value = 0 if s.op == '*' && (s.a == 0 || s.b == 0)
      end
      return [s, nil] if value.nil?
      r = Instruction.new(kind: :copy, x: s.x, a: value)
      [r, "fold #{r}"]
    end
    def self.replace(function, replacements)
      function.code = function.code.flat_map { |s| replacements.fetch(s.object_id, [s]) }
    end
    def self.cse(function, expression, sources, candidates)
      function.temp_id += 1
      name = "_t#{function.temp_id}"
      replacements = {}
      sources.each do |s|
        r = s.dup
        r.x = name
        replacements[s.object_id] = [r, Instruction.new(kind: :copy, x: s.x, a: name)]
      end
      candidates.each { |s| replacements[s.object_id] = [Instruction.new(kind: :copy, x: s.x, a: name)] }
      replace(function, replacements)
      name
    end
    def self.hoist(function, loop_info, moving)
      h = loop_info.header
      outside = h.preds.reject { |p| loop_info.blocks.include?(p) }
      pre = outside.first
      ids = moving.map(&:object_id).to_set
      code = function.code.reject { |s| ids.include?(s.object_id) }
      if h.id != 1 && outside.length == 1 && pre.succs == [h]
        last = pre.instructions.last
        index = code.index(last)
        index += 1 unless %i[goto if].include?(last.kind)
        code.insert(index, *moving)
        destination = pre.to_s
      else
        function.preheader_id += 1
        label = "_p#{function.preheader_id}"
        first = h.labels.empty? ? h.instructions.first : h.labels.first
        index = code.index(first)
        code.insert(index, label, *moving)
        outside.each do |p|
          s = p.instructions.last
          s.target = label if %i[goto if].include?(s.kind) && h.labels.include?(s.target)
        end
        destination = "new #{label}"
      end
      function.code = code
      destination
    end
    def self.unreachable(function, cfg)
      records, removed = [], Set.new
      (cfg.blocks - cfg.reachable).each do |b|
        records << "remove block #{b}"
        b.instructions.each { |s| removed << s.object_id }
        b.labels.each { |l| removed << l.object_id }
      end
      function.code.reject! { |s| removed.include?(s.object_id) }
      jumps = Set.new
      function.code.each_with_index do |s, i|
        next unless s.is_a?(Instruction) && %i[goto if].include?(s.kind)
        labels = function.code.drop(i + 1).take_while { |v| v.is_a?(String) }
        next unless labels.include?(s.target)
        jumps << s.object_id
        records << "remove jump ##{s.number}"
      end
      function.code.reject! { |s| jumps.include?(s.object_id) }
      targets = function.instructions.filter_map { |s| s.target if %i[goto if].include?(s.kind) }.to_set
      function.code.reject! do |s|
        unused = s.is_a?(String) && !targets.include?(s)
        records << "remove label #{s}" if unused
        unused
      end
      records
    end
  end
end
