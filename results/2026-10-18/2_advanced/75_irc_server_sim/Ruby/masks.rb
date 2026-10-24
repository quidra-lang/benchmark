require_relative 'protocol'

module Masks
  def self.matches?(mask, value)
    mask, value = Protocol.fold(mask), Protocol.fold(value)
    pattern = position = restart = 0
    star = nil
    while position < value.length
      if mask[pattern] == '*'
        star = pattern
        pattern += 1
        restart = position
      elsif pattern < mask.length && (mask[pattern] == '?' || mask[pattern] == value[position])
        pattern += 1
        position += 1
      elsif star
        restart += 1
        position = restart
        pattern = star + 1
      else
        return false
      end
    end
    pattern += 1 while mask[pattern] == '*'
    pattern == mask.length
  end

  def self.normalize(argument)
    return argument if argument.include?('!') && argument.include?('@')
    return '*!' + argument if argument.include?('@')
    return argument + '@*' if argument.include?('!')
    return '*!*@' + argument if argument.include?('.')
    argument + '!*@*'
  end
end
