require 'set'

module Strips
  Atom = Struct.new(:predicate, :terms)
  Schema = Struct.new(:name, :parameters, :condition, :effects, :cost)
  Domain = Struct.new(:name, :parents, :type_order, :predicates, :actions, :fluent, :static, :diagnostics)
  Problem = Struct.new(:name, :objects, :initial, :goals, :diagnostics)

  def self.expressions(text)
    cleaned = text.lines.map { |line| line.split(';', 2).first.to_s }.join("\n")
    roots = []
    stack = [roots]
    cleaned.scan(/\(|\)|[^ ()\n]+/).each do |token|
      case token
      when '('
        child = []
        stack.last << child
        stack << child
      when ')' then stack.pop
      else stack.last << token
      end
    end
    roots
  end

  def self.typed_list(words)
    result, pending, index = [], [], 0
    while index < words.length
      if words[index] == '-'
        pending.each { |name| result << [name, words[index + 1]] }
        pending.clear
        index += 2
      else
        pending << words[index]
        index += 1
      end
    end
    result + pending.map { |name| [name, 'object'] }
  end

  def self.atom(expression) = Atom.new(expression.first, expression.drop(1))
  def self.elements(expression, empty: true)
    conjunction = expression.first == 'and' && expression.drop(1).all? { |item| item.is_a?(Array) }
    conjunction && (empty || expression.length > 1) ? expression.drop(1) : [expression]
  end
  def self.literal(expression)
    expression.first == 'not' && expression.length == 2 && expression[1].is_a?(Array) ? [false, atom(expression[1])] : [true, atom(expression)]
  end

  def self.read_domain(text)
    expression = expressions(text).first
    domain = Domain.new(expression[1][1], {'object' => nil}, ['object'], {}, [])
    expression.drop(2).each do |section|
      case section.first
      when ':types'
        section.drop(1).each do |name|
          next if name == '-' || domain.parents.key?(name)
          domain.parents[name] = 'object'
          domain.type_order << name
        end
        typed_list(section.drop(1)).each { |name, parent| domain.parents[name] = parent }
      when ':predicates'
        section.drop(1).each { |declaration| domain.predicates[declaration.first] = typed_list(declaration.drop(1)).map(&:last) }
      when ':action'
        fields = section.drop(2).each_slice(2).to_h
        condition = fields.key?(':precondition') ? elements(fields[':precondition']).map { |item| literal(item) } : []
        effects, cost = [], 1
        elements(fields[':effect'], empty: false).each do |item|
          if item.first == 'increase' && item.length == 3 && item[1] == ['total-cost']
            cost = item[2].to_i
          else
            effects << literal(item)
          end
        end
        domain.actions << Schema.new(section[1], typed_list(fields[':parameters']), condition, effects, cost)
      end
    end
    domain
  end

  def self.read_problems(text)
    expressions(text).map do |expression|
      sections = expression.drop(2).to_h { |section| [section.first, section.drop(1)] }
      Problem.new(expression[1][1], typed_list(sections[':objects']).to_h,
                  sections[':init'].map { |item| atom(item) }, elements(sections[':goal'].first, empty: false).map { |item| atom(item) }, [])
    end
  end
end
