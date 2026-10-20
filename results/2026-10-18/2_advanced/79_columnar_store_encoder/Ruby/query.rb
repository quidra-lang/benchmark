class QueryParser
  def initialize(text)
    @tokens = text.scan(/'[a-z0-9_-]*'|[A-Z]+|[a-z][a-z0-9_]*|-?[0-9]+|<=|>=|<>|[=<>(),*]/)
    @position = 0
  end

  def peek
    @tokens[@position]
  end

  def take(expected = nil)
    token = @tokens[@position]
    @position += 1
    raise ArgumentError, "expected #{expected}" if expected && token != expected
    token
  end

  def accept(token)
    return false unless peek == token
    @position += 1
    true
  end

  def parse
    take('SELECT')
    items = nil
    unless accept('*')
      items = [item]
      items << item while accept(',')
    end
    condition = condition() if accept('WHERE')
    group = nil
    if accept('GROUP')
      take('BY')
      group = take
    end
    order, descending = nil, false
    if accept('ORDER')
      take('BY')
      order = take
      descending = accept('DESC')
      accept('ASC') unless descending
    end
    limit = take.to_i if accept('LIMIT')
    { items: items, condition: condition, group: group, order: order, descending: descending, limit: limit }
  end

  def item
    operation = take
    return ['COLUMN', operation] if /\A[a-z]/.match?(operation)
    take('(')
    operation = 'COUNT_DISTINCT' if accept('DISTINCT')
    column = accept('*') ? nil : take
    take(')')
    [operation, column]
  end

  def literal
    token = take
    return ['STRING', token[1...-1]] if token.start_with?("'")
    return ['BOOL', token == 'TRUE'] if %w[TRUE FALSE].include?(token)
    ['INT', token.to_i]
  end

  def condition
    tree = conjunction
    tree = ['OR', tree, conjunction] while accept('OR')
    tree
  end

  def conjunction
    tree = negation
    tree = ['AND', tree, negation] while accept('AND')
    tree
  end

  def negation
    return ['NOT', negation] if accept('NOT')
    if accept('(')
      tree = condition
      take(')')
      return tree
    end
    column, operation = take, take
    literals = []
    case operation
    when 'IS'
      operation = accept('NOT') ? 'IS_NOT_NULL' : 'IS_NULL'
      take('NULL')
    when 'BETWEEN'
      literals << literal
      take('AND')
      literals << literal
    when 'IN'
      take('(')
      literals << literal
      literals << literal while accept(',')
      take(')')
    else literals << literal
    end
    [operation, column, literals]
  end
end
