class Value
  attr_reader :kind, :data
  def initialize(kind, data = nil)
    @kind, @data = kind, data
  end

  UNSET = new(:unset).freeze
  def self.number(n)
    new(:number, n)
  end
  def self.string(s)
    new(:string, s)
  end
  def self.input(s)
    first, last = 0, s.length
    first += 1 while first < last && [' ', "\t", "\n"].include?(s[first])
    last -= 1 while last > first && [' ', "\t", "\n"].include?(s[last - 1])
    trimmed = s[first...last]
    body = ['+', '-'].include?(trimmed[0]) ? trimmed[1..] : trimmed
    numeric = !body.empty? && body.each_char.all? { |c| ('0'..'9').cover?(c) }
    new(numeric ? :strnum : :string, s)
  end

  def number
    return @data if @kind == :number
    return 0 if @kind == :unset
    text, at, sign = @data, 0, 1
    at += 1 while [' ', "\n", "\t"].include?(text[at])
    if ['+', '-'].include?(text[at])
      sign = -1 if text[at] == '-'
      at += 1
    end
    first = at
    at += 1 while text[at] && ('0'..'9').cover?(text[at])
    first == at ? 0 : sign * text[first...at].to_i
  end

  def string
    @kind == :unset ? '' : @data.to_s
  end

  def truth
    @kind == :string ? !@data.empty? : number != 0
  end

  def compare(other)
    @kind != :string && other.kind != :string ? number <=> other.number : string <=> other.string
  end

  def display
    return '(uninitialized)' if @kind == :unset
    return string if @kind == :number
    escaped = string.bytes.map do |c|
      { 34 => '\\"', 92 => '\\\\', 10 => '\\n', 9 => '\\t' }.fetch(c) do
        (32..126).cover?(c) ? c.chr : format('\\%03o', c)
      end
    end.join
    '"' + escaped + '"' + (@kind == :strnum ? ' (strnum)' : '')
  end

  def self.integer_key?(s)
    return true if s == '0'
    body = s.start_with?('-') ? s[1..] : s
    !body.empty? && ('1'..'9').cover?(body[0]) && body.each_char.all? { |c| ('0'..'9').cover?(c) }
  end

  def self.sorted_keys(array)
    array.keys.sort_by { |key| integer_key?(key) ? [0, key.to_i] : [1, key] }
  end

  def self.split(text, separator)
    return [] if text.empty?
    return text.chars if separator.empty?
    if separator == ' '
      parts, current = [], +''
      text.each_char do |c|
        if [' ', "\t", "\n"].include?(c)
          parts << current unless current.empty?
          current = +''
        else
          current << c
        end
      end
      parts << current unless current.empty?
      parts
    else
      parts, start = [], 0
      while (at = text.index(separator, start))
        parts << text[start...at]
        start = at + separator.length
      end
      parts << text[start..]
    end
  end
end

class Fields
  attr_reader :record, :fields
  def initialize
    @record, @fields = Value.string(''), []
  end

  def set(text, fs)
    @record = Value.input(text)
    @fields = Value.split(text, fs).map { |part| Value.input(part) }
  end

  def read(k)
    k.zero? ? @record : @fields.fetch(k - 1, Value::UNSET)
  end

  def rebuild(ofs)
    @record = Value.input(@fields.map(&:string).join(ofs))
  end

  def assign(k, value, fs, ofs)
    if k.zero?
      set(value.string, fs)
    else
      @fields << Value.string('') while @fields.length < k
      @fields[k - 1] = value
      rebuild(ofs)
    end
  end

  def resize(n, ofs)
    @fields = @fields.take(n)
    @fields << Value.string('') while @fields.length < n
    rebuild(ofs)
  end
end
