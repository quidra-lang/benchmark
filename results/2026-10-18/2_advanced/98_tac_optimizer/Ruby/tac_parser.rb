module TAC
  KINDS = %i[copy bin load store goto if param call return read print].freeze
  Instruction = Struct.new(:kind, :x, :a, :b, :op, :array, :target, :callee, :argc, :number, keyword_init: true) do
    def definition = x
    def operand_fields
      case kind
      when :copy, :load, :param, :return, :print then a.nil? ? [] : [:a]
      when :bin, :if, :store then %i[a b]
      else []
      end
    end
    def uses = operand_fields.map { |f| public_send(f) }.grep(String)
    def expression
      return [:bin, op, a, b] if kind == :bin
      [:load, array, a] if kind == :load
    end
    def to_s
      case kind
      when :copy then "#{x} = #{a}"
      when :bin then "#{x} = #{a} #{op} #{b}"
      when :load then "#{x} = #{array}[#{a}]"
      when :store then "#{array}[#{a}] = #{b}"
      when :goto then "goto #{target}"
      when :if then "if #{a} #{op} #{b} goto #{target}"
      when :param, :print then "#{kind} #{a}"
      when :read then "read #{x}"
      when :return then a.nil? ? 'return' : "return #{a}"
      when :call then "#{x ? "#{x} = " : ''}call #{callee} #{argc}"
      end
    end
  end
  Function = Struct.new(:name, :params, :code, :temp_id, :preheader_id, keyword_init: true) do
    def instructions = code.grep(Instruction)
    def number!
      instructions.each_with_index { |s, i| s.number = i + 1 }
    end
    def lines = [(['func', name] + params).join(' ')] + code.map { |s| s.is_a?(String) ? "#{s}:" : "    #{s}" } + ['end']
  end
  Program = Struct.new(:arrays, :functions) do
    def to_s
      sections = []
      sections << arrays.map { |n, z| "array #{n} #{z}" }.join("\n") unless arrays.empty?
      sections.concat(functions.map { |f| f.lines.join("\n") })
      sections.join("\n\n") + "\n"
    end
  end
  def self.operand(word) = word.match?(/\A-?\d+\z/) ? word.to_i : word
  def self.expression_text(e) = e[0] == :bin ? "#{e[2]}#{e[1]}#{e[3]}" : "#{e[1]}[#{e[2]}]"
  def self.calculate(op, a, b)
    case op
    when '+' then a + b
    when '-' then a - b
    when '*' then a * b
    when '/', '%' then q = a.abs.div(b.abs) * (a.negative? == b.negative? ? 1 : -1); op == '/' ? q : a - b * q
    when '<' then a < b ? 1 : 0
    when '<=' then a <= b ? 1 : 0
    when '>' then a > b ? 1 : 0
    when '>=' then a >= b ? 1 : 0
    when '==' then a == b ? 1 : 0
    when '!=' then a != b ? 1 : 0
    end
  end
  def self.parse(path)
    arrays, functions, current = [], [], nil
    File.foreach(path) do |line|
      w = line.split
      next if w.empty? || w[0].start_with?('#')
      case w[0]
      when 'array' then arrays << [w[1], w[2].to_i]
      when 'func'
        current = Function.new(name: w[1], params: w.drop(2), code: [], temp_id: 0, preheader_id: 0)
        functions << current
      when 'end' then current = nil
      else
        if w.length == 1 && w[0].end_with?(':')
          current.code << w[0][0...-1]
          next
        end
        s = Instruction.new
        case w[0]
        when 'goto' then s.kind, s.target = :goto, w[1]
        when 'if' then s.kind, s.a, s.op, s.b, s.target = :if, operand(w[1]), w[2], operand(w[3]), w[5]
        when 'param', 'print', 'return' then s.kind, s.a = w[0].to_sym, w[1] && operand(w[1])
        when 'read' then s.kind, s.x = :read, w[1]
        when 'call' then s.kind, s.callee, s.argc = :call, w[1], w[2].to_i
        else
          if (m = /\A([^\[]+)\[(.*)\]\z/.match(w[0]))
            s.kind, s.array, s.a, s.b = :store, m[1], operand(m[2]), operand(w[2])
          else
            s.x = w[0]
            if w[2] == 'call'
              s.kind, s.callee, s.argc = :call, w[3], w[4].to_i
            elsif w.length == 5
              s.kind, s.a, s.op, s.b = :bin, operand(w[2]), w[3], operand(w[4])
            elsif (m = /\A([^\[]+)\[(.*)\]\z/.match(w[2]))
              s.kind, s.array, s.a = :load, m[1], operand(m[2])
            else
              s.kind, s.a = :copy, operand(w[2])
            end
          end
        end
        current.code << s
      end
    end
    Program.new(arrays, functions)
  end
end
