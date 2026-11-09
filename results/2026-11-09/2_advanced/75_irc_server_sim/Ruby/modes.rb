require_relative 'protocol'

module Modes
  def self.channel_items(mode, arguments)
    sign = '+'
    position = 0
    items = []
    mode.each_char do |character|
      if '+-'.include?(character)
        sign = character
        next
      end
      argument = nil
      if 'ovbk'.include?(character) || (character == 'l' && sign == '+')
        if position < arguments.length
          argument = arguments[position]
          position += 1
        end
      end
      if character == 'k' && sign == '-'
        argument = '*'
      elsif character == 'l' && sign == '+'
        argument = nil unless argument && Protocol.digits?(argument) && argument.length <= 4 && argument.to_i.positive?
      end
      items << [sign, character, argument]
    end
    items
  end

  def self.change_string(changes)
    mode, arguments = '', []
    previous = nil
    changes.each do |sign, character, argument|
      mode += sign if sign != previous
      previous = sign
      mode += character
      arguments << argument unless argument.nil?
    end
    mode + arguments.map { |argument| ' ' + argument }.join
  end
end
