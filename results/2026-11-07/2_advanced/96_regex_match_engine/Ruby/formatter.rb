module Formatter
  def self.character(c)
    (33..126).cover?(c) && ![92, 93, 94, 45].include?(c) ? c.chr : format('\\x%02X', c)
  end

  def self.set(codes, negated = false)
    runs = []
    codes.sort.uniq.each do |c|
      if !runs.empty? && runs[-1][-1] + 1 == c
        runs[-1] << c
      else
        runs << [c]
      end
    end
    content = runs.map do |run|
      if run.length < 3
        run.map { |c| character(c) }.join
      else
        "#{character(run.first)}-#{character(run.last)}"
      end
    end.join
    "[#{negated ? '^' : ''}#{content}]"
  end

  def self.instruction(i)
    op, a, b = i
    case op
    when :char then "CHAR #{character(a)}"
    when :class then "CLASS #{set(a, b)}"
    when :split then "SPLIT #{a}, #{b}"
    when :look then "LOOK #{a} #{b}"
    else [op.to_s.upcase, a].compact.join(' ')
    end
  end

  def self.quote(text)
    '"' + text.each_char.map { |c| { "\\" => "\\\\", '"' => '\\"', "\n" => '\\n', "\t" => '\\t' }.fetch(c, c) }.join + '"'
  end
end
