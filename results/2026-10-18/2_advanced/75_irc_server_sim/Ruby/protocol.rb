module Protocol
  LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'.freeze
  SPECIAL = "[]\\`_^{}|".freeze
  FOLD = ('A'..'Z').zip(('a'..'z')).to_h.merge('[' => '{', ']' => '}', '\\' => '|', '^' => '~').freeze

  def self.fold(value)
    value.each_char.map { |character| FOLD.fetch(character, character) }.join
  end

  def self.digits?(value)
    !value.empty? && value.each_char.all? { |character| character.between?('0', '9') }
  end

  def self.valid_nickname?(value)
    !value.empty? && (LETTERS + SPECIAL).include?(value[0]) &&
      value[1..].each_char.all? { |character| (LETTERS + SPECIAL + '0123456789-').include?(character) }
  end

  def self.valid_channel?(value, maximum)
    value.length.between?(2, maximum) && value.start_with?('#') && !value.include?(':')
  end

  def self.parse(raw)
    position = 0
    if raw.start_with?(':')
      position = raw.index(' ')
      return ['', []] unless position
    end
    position += 1 while raw[position] == ' '
    start = position
    position += 1 while position < raw.length && raw[position] != ' '
    command = raw[start...position].upcase
    parameters = []
    while position < raw.length
      position += 1 while raw[position] == ' '
      break if position == raw.length
      if raw[position] == ':'
        parameters << raw[position + 1..]
        break
      elsif parameters.length == 14
        parameters << raw[position..]
        break
      end
      start = position
      position += 1 while position < raw.length && raw[position] != ' '
      parameters << raw[start...position]
    end
    [command, parameters]
  end
end
