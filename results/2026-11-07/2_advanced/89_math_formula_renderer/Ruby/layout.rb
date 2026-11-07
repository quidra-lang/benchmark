require_relative 'boxes'

module Layout
  TYPES = %w[ordinary operator binary relation open close punctuation].freeze
  SPACING = [[0, 1, 'B', 'R', 0, 0, 0], [1, 1, nil, 'R', 0, 0, 0],
             ['B', 'B', nil, nil, 'B', nil, nil], ['R', 'R', nil, 0, 'R', 0, 0],
             [0, 0, nil, 0, 0, 0, 0], [0, 1, 'B', 'R', 0, 0, 0],
             ['P', 'P', nil, 'P', 'P', 'P', 'P']].freeze

  def self.types(node)
    case node.kind
    when 'delim' then return ['open', 'close']
    when 'script' then return types(node.children[0])
    when 'overset', 'underset' then return types(node.children[1])
    when 'command' then type = Boxes::COMMAND_TYPES.fetch(node.value)
    when 'symbol' then type = Boxes::SYMBOL_TYPES.fetch(node.value, 'ordinary')
    else type = 'ordinary'
    end
    [type, type]
  end

  def self.convert(nodes)
    result = nodes.map { |node| types(node) }
    result.each_with_index do |current, i|
      if current[0] == 'binary' && (i.zero? || %w[binary operator relation open punctuation].include?(result[i - 1][1]))
        current.replace(%w[ordinary ordinary])
      end
      if %w[relation close punctuation].include?(current[0]) && i.positive? && result[i - 1][1] == 'binary'
        result[i - 1].replace(%w[ordinary ordinary])
      end
    end
    result[-1].replace(%w[ordinary ordinary]) if !result.empty? && result[-1][1] == 'binary'
    result
  end

  def self.word?(node)
    return word?(node.children[0]) if node.kind == 'script'
    node.kind == 'command' && (Lexer::GREEK.include?(node.value[1..]) || node.value == '\\infty')
  end

  def self.alphanumeric?(node)
    return true if %w[identifier number].include?(node.kind) || word?(node)
    return alphanumeric?(node.children[0]) if node.kind == 'script'
    node.kind == 'accent' && %w[overline hat vec dot tilde].include?(node.value) && alphanumeric?(node.children[0])
  end

  def self.spacing(nodes, style, params)
    converted = convert(nodes)
    values = { 'B' => style == 'normal' ? params['bin_space'] : 0,
               'R' => style == 'normal' ? params['rel_space'] : 0,
               'P' => style == 'normal' ? params['punct_space'] : 0 }
    gaps = nodes.each_cons(2).with_index.map do |(first, second), i|
      if alphanumeric?(first) && alphanumeric?(second) && (word?(first) || word?(second))
        1
      else
        entry = SPACING[TYPES.index(converted[i][1])][TYPES.index(converted[i + 1][0])]
        entry.is_a?(String) ? values.fetch(entry) : entry
      end
    end
    [converted, gaps]
  end

  def self.row(children, gaps, description = 'row', roles = nil)
    ascent = children.map(&:baseline).max || 0
    descent = children.map(&:descent).max || 0
    box = Box.new(children.sum(&:width) + gaps.sum, ascent + descent + 1, ascent, description)
    x = 0
    children.each_with_index do |child, i|
      box.add(child, x, ascent - child.baseline, roles ? roles[i] : '')
      x += child.width + (gaps[i] || 0)
    end
    box
  end
end
