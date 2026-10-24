require_relative 'expressions'

Element = Struct.new(:kind, :id, :behavior, :parent, :targets, :children,
                     :condition, :obligations, :advice)

module PolicyParser
  def self.target(text)
    text.split(' | ').map do |alternative|
      alternative.split(' & ').map do |clause|
        reference, operator, literal = clause.split(' ')
        [reference.delete_suffix('!'), reference.end_with?('!'), operator, Expressions.parse(literal)]
      end
    end
  end

  def self.read(path = 'input/policies.txt')
    elements, stack = [], []
    File.foreach(path) do |raw|
      line = raw.strip
      next if line.empty? || line.start_with?('#')
      keyword, rest = line.split(' ', 2)
      case keyword
      when 'POLICYSET', 'POLICY', 'RULE'
        id, behavior = rest.split(' ')
        element = Element.new(keyword.downcase, id, behavior, stack.last, [], [], nil, [], [])
        stack.last.children << element unless stack.empty?
        elements << element
        stack << element
      when 'END'
        stack.pop
      when 'TARGET'
        stack.last.targets << target(rest)
      when 'CONDITION'
        stack.last.condition = Expressions.parse(rest)
      else
        effect, id, arguments = rest.split(' ', 3)
        parsed = arguments ? arguments.split(';').map { |part|
          name, expression = part.strip.split('=', 2)
          [name, Expressions.parse(expression)]
        } : []
        collection = keyword == 'OBLIGATION' ? stack.last.obligations : stack.last.advice
        collection << [effect, id, parsed]
      end
    end
    [elements.first, elements]
  end
end
