require_relative 'rational'

module LPParser
  def self.name?(word)
    word && /\A[a-z][a-z0-9_]*\z/.match?(word) && !%w[bounds integer binary free inf].include?(word)
  end

  def self.expression(words)
    position, sign, terms = 0, 1, []
    if words[0] == '-'
      position, sign = 1, -1
    end
    while position < words.length
      coefficient = Q.read(words[position])
      if coefficient
        return nil unless name?(words[position + 1])
        name = words[position + 1]
        position += 2
      elsif name?(words[position])
        coefficient, name = Q::ONE, words[position]
        position += 1
      else
        return nil
      end
      terms << [name, sign * coefficient]
      return terms if position == words.length
      return nil unless %w[+ -].include?(words[position])
      sign = words[position] == '+' ? 1 : -1
      position += 1
    end
    nil
  end

  def self.named_expression(words)
    return nil if words.length < 2 || !words[0].end_with?(':')
    name, terms = words[0][0...-1], expression(words.drop(1))
    name?(name) && terms ? [name, terms] : nil
  end

  def self.constraint(words, line)
    return nil if words.length < 4 || !%w[<= >= =].include?(words[-2])
    rhs, named = Q.read(words[-1], true), named_expression(words[0...-2])
    return nil unless rhs && named
    {line: line, name: named[0], terms: named[1], op: words[-2], rhs: rhs}
  end

  def self.bound(words, line)
    if words.length == 2 && name?(words[0]) && words[1] == 'free'
      return {line: line, name: words[0], kind: :both, lower: nil, upper: nil}
    end
    if words.length == 3 && name?(words[0])
      name, op, text = words
      value = Q.read(text, true)
      return {line: line, name: name, kind: :lower, lower: value} if op == '>=' && (value || text == '-inf')
      return {line: line, name: name, kind: :upper, upper: value} if op == '<=' && (value || text == 'inf')
      return {line: line, name: name, kind: :both, lower: value, upper: value} if op == '=' && value
    end
    if words.length == 5 && words[1] == '<=' && words[3] == '<=' && name?(words[2])
      lower, upper = Q.read(words[0], true), Q.read(words[4], true)
      if (lower || words[0] == '-inf') && (upper || words[4] == 'inf')
        return {line: line, name: words[2], kind: :both, lower: lower, upper: upper}
      end
    end
    nil
  end

  def self.block(name, body, ending)
    result = {name: name, error: nil, constraints: [], bounds: [], integers: [], binaries: []}
    state = :a
    body.each do |line, text|
      words, accepted = text.split(' '), false
      case state
      when :a
        if %w[maximize minimize].include?(text)
          result[:direction], state, accepted = text, :b, true
        end
      when :b
        named = named_expression(words)
        result[:objective], state, accepted = named[1], :c, true if named
      when :c
        state, accepted = :d, true if text == 'subject to'
      when :d, :e
        if state == :e && %w[bounds integer binary].include?(text)
          state, accepted = {'bounds'=>:f, 'integer'=>:g, 'binary'=>:h}[text], true
        elsif (item = constraint(words, line))
          result[:constraints] << item
          state, accepted = :e, true
        end
      when :f
        if %w[integer binary].include?(text)
          state, accepted = (text == 'integer' ? :g : :h), true
        elsif (item = bound(words, line))
          result[:bounds] << item
          accepted = true
        end
      when :g, :h
        if state == :g && text == 'binary'
          state, accepted = :h, true
        elsif words.all? { |word| name?(word) }
          result[state == :g ? :integers : :binaries] << [line, words]
          accepted = true
        end
      end
      unless accepted
        result[:error] = [line, 'syntax error']
        return result
      end
    end
    result[:error] = [ending, 'syntax error'] if %i[a b c d].include?(state)
    result
  end

  def self.read_models
    models, name, body = [], nil, []
    File.foreach('input/models.lp', chomp: true).with_index(1) do |text, line|
      next if text.empty? || text.start_with?('#')
      if name.nil?
        name, body = text.split(' ')[1], []
      elsif text == 'end'
        models << block(name, body, line)
        name = nil
      else
        body << [line, text]
      end
    end
    models
  end

  def self.read_settings
    lines = File.readlines('input/params.txt', chomp: true)
    settings = {level: lines[0].split[1].to_i, limit: lines[1].split[1].to_i, logs: {}, limits: {}}
    lines.drop(2).each do |line|
      kind, name, value = line.split(' ')
      settings[kind == 'log' ? :logs : :limits][name] = value.to_i
    end
    settings
  end
end
