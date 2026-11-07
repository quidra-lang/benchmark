class Streams
  attr_reader :options, :operands, :outputs, :getlines

  def self.valid_name?(name)
    !name.empty? && !name.start_with?('.') && name.each_char.all? { |c| Lexer.letter?(c) || Lexer.digit?(c) || '.-'.include?(c) }
  end

  def initialize(lines)
    @options, @operands = [], []
    lines.each do |line|
      if line.start_with?('-F ')
        @options << ['FS', line[3..]]
      elsif line.start_with?('-v ')
        @options << line[3..].split('=', 2)
      else
        name, value = line.split('=', 2)
        if value && Lexer.name?(name)
          @operands << { kind: :assignment, name: name, value: value }
        else
          @operands << { kind: :file, name: line, records: 0 }
        end
      end
    end
    @operand_index, @current, @current_lines, @record_index = 0, nil, [], 0
    @outputs = { 'stdout.txt' => { text: +'', writes: 0, open: true } }
    @getlines = {}
  end

  def read_main
    loop do
      if @record_index < @current_lines.length
        line = @current_lines[@record_index]
        @record_index += 1
        @current[:records] += 1
        return line
      end
      return nil if @operand_index >= @operands.length
      operand = @operands[@operand_index]
      @operand_index += 1
      if operand[:kind] == :assignment
        yield(:assignment, operand[:name], operand[:value])
      else
        @current = operand
        @current_lines = File.readlines("input/#{operand[:name]}", chomp: true)
        @record_index = 0
        yield(:file, operand[:name], nil)
      end
    end
  end

  def read_getline(name)
    entry = (@getlines[name] ||= { opened: false, open: false, reads: 0 })
    unless entry[:open]
      return [-1, nil] unless self.class.valid_name?(name) && File.file?("input/#{name}")
      entry[:lines] = File.readlines("input/#{name}", chomp: true)
      entry[:index], entry[:opened], entry[:open] = 0, true, true
    end
    return [0, nil] if entry[:index] >= entry[:lines].length
    text = entry[:lines][entry[:index]]
    entry[:index] += 1
    entry[:reads] += 1
    [1, text]
  end

  def write(text, name = 'stdout.txt', mode = nil, token = nil)
    if mode && (!self.class.valid_name?(name) || ['stdout.txt', 'stats.txt'].include?(name))
      raise AwkRuntimeError.new('invalid output file name', token)
    end
    entry = (@outputs[name] ||= { text: +'', writes: 0, open: false })
    unless entry[:open]
      entry[:text] = +'' if mode == '>'
      entry[:open] = true
    end
    entry[:text] << text
    entry[:writes] += 1
  end

  def close(name)
    closed = false
    if name != 'stdout.txt' && @outputs[name] && @outputs[name][:open]
      @outputs[name][:open] = false
      closed = true
    end
    if @getlines[name] && @getlines[name][:open]
      @getlines[name][:open] = false
      closed = true
    end
    closed ? 0 : -1
  end

  def save
    @outputs.each { |name, entry| File.write("output/#{name}", entry[:text]) }
  end
end
