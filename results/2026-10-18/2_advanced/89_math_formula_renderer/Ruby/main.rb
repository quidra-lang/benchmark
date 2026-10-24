require 'fileutils'
require_relative 'lexer'
require_relative 'parser'
require_relative 'boxes'
require_relative 'layout'
require_relative 'canvas'

class Formula
  attr_reader :number, :line, :nodes, :tokens, :tag, :label, :error, :warnings
  attr_accessor :tag_string

  def initialize(number, line)
    @number, @line = number, line
    @warnings = []
    @tokens = Lexer.tokenize(line)
    Parser.check_braces(@tokens)
    parser = Parser.new(@tokens)
    @nodes = parser.parse
    @tag, @label = parser.tag, parser.label
  rescue Lexer::FormulaError => e
    @error = [e.column, e.message]
  end
end

def reference_table(formulas)
  counter = 0
  formulas.reject(&:error).each do |formula|
    if formula.tag
      formula.tag_string = "(#{formula.tag.value})"
    elsif formula.label
      counter += 1
      formula.tag_string = "(#{counter})"
    end
  end
  references = {}
  formulas.each do |formula|
    next if formula.error || !formula.label
    label = formula.label
    if references.key?(label.value)
      formula.warnings << [label.column, "duplicate label \"#{label.value}\""]
    else
      references[label.value] = formula.tag_string
    end
  end
  references
end

def walk_nodes(node, &block)
  yield node
  children = node.kind == 'matrix' ? node.children.flatten(1) : node.children
  children.compact.each { |child| walk_nodes(child, &block) }
end

def collect_warnings(formula, references)
  pairs = { '(' => ')', '[' => ']', '|' => '|', '\\{' => '\\}' }
  formula.nodes.each do |element|
    walk_nodes(element) do |node|
      message = nil
      if node.kind == 'identifier' && Lexer::COMMAND_NAMES.include?(node.value)
        message = "#{node.value} is a command name; write \\" + node.value
      elsif node.kind == 'reference' && !references.key?(node.value)
        message = "undefined reference \"#{node.value}\""
      elsif node.kind == 'delim'
        left, right = node.value
        message = '\\left' + left + ' closed by \\right' + right if left != '.' && right != '.' && pairs[left] != right
      end
      formula.warnings << [node.column, message] if message
    end
  end
  formula.warnings.sort_by!(&:first)
end

class Typesetter
  def initialize(params, references)
    @params, @references = params, references
  end

  def typeset(node, style = 'normal')
    return atom(node, style) if (Parser::ATOMS + ['reference']).include?(node.kind)
    public_send(node.kind, node, style)
  end

  def center(box, width)
    (width - box.width) / 2
  end

  def draw_delimiter(box, delimiter, x, height)
    Boxes.delimiter_glyph(delimiter, height).each_with_index { |character, y| box.draw(character, x, y) }
  end

  def atom(node, style)
    if node.kind == 'text'
      description, display = "text \"#{node.value}\"", node.value
    elsif node.kind == 'reference'
      description, display = "eqref \"#{node.value}\"", @references.fetch(node.value, '(??)')
    else
      description = "atom \"#{node.value}\""
      display = node.kind == 'command' ? Boxes::DISPLAY.fetch(node.value) : node.value
    end
    glyph = node.kind == 'command' && style == 'normal' ? Boxes::LARGE_GLYPHS[node.value] : nil
    if glyph
      box = Box.new(glyph[0].size, 3, 1, description)
      glyph.each_with_index { |text, y| box.draw(text, 0, y) }
    else
      box = Box.new(display.size, 1, 0, description)
      box.draw(display)
    end
    box
  end

  def row(node, style)
    _, gaps = Layout.spacing(node.children, style, @params)
    Layout.row(node.children.map { |child| typeset(child, style) }, gaps)
  end

  def script(node, style)
    base_node, sub_node, sup_node = node.children
    base = typeset(base_node, style)
    sub = typeset(sub_node, 'script') if sub_node
    sup = typeset(sup_node, 'script') if sup_node
    sw, sh = sub ? [sub.width, sub.height] : [0, 0]
    pw, ph = sup ? [sup.width, sup.height] : [0, 0]
    stacked = style == 'normal' &&
              ((base_node.kind == 'command' && ['\\sum', '\\prod', '\\lim', '\\max', '\\min'].include?(base_node.value)) ||
               (base_node.kind == 'accent' && %w[overbrace underbrace].include?(base_node.value)))
    if stacked
      width = [base.width, sw, pw].max
      box = Box.new(width, ph + base.height + sh, ph + base.baseline, 'limits')
      box.add(base, center(base, width), ph, 'base: ')
      box.add(sub, center(sub, width), ph + base.height, 'sub: ') if sub
      box.add(sup, center(sup, width), 0, 'sup: ') if sup
      return box
    end
    tp = (base.baseline.zero? ? -1 : 0) - ph + 1
    ts = base.descent.zero? ? base.height : base.height - 1
    top = sup ? [0, tp].min : 0
    bottom = sub ? [base.height - 1, ts + sh - 1].max : base.height - 1
    box = Box.new(base.width + [sw, pw].max, bottom - top + 1, base.baseline - top, 'scripts')
    box.add(base, 0, -top, 'base: ')
    box.add(sub, base.width, ts - top, 'sub: ') if sub
    box.add(sup, base.width, tp - top, 'sup: ') if sup
    box
  end

  def frac(node, style)
    numerator, denominator = node.children.map { |child| typeset(child, style) }
    if style == 'normal'
      width = [numerator.width, denominator.width].max + 2
      box = Box.new(width, numerator.height + 1 + denominator.height, numerator.height, 'frac')
      box.add(numerator, center(numerator, width), 0, 'num: ')
      box.add(denominator, center(denominator, width), numerator.height + 1, 'den: ')
      box.draw('-' * width, 0, numerator.height)
      return box
    end
    numerator = delimit(numerator, '(', ')') if %w[row frac].include?(node.children[0].kind)
    denominator = delimit(denominator, '(', ')') if %w[row frac].include?(node.children[1].kind)
    slash = Box.new(1, 1, 0, 'atom "/"')
    slash.draw('/')
    Layout.row([numerator, slash, denominator], [0, 0], 'slash', ['num: ', '', 'den: '])
  end

  def binom(node, style)
    upper, lower = node.children.map { |child| typeset(child, style) }
    width = [upper.width, lower.width].max
    height = upper.height + 1 + lower.height
    box = Box.new(width + 2, height, upper.height, 'binom')
    box.add(upper, center(upper, width) + 1, 0, 'upper: ')
    box.add(lower, center(lower, width) + 1, upper.height + 1, 'lower: ')
    draw_delimiter(box, '(', 0, height)
    draw_delimiter(box, ')', width + 1, height)
    box
  end

  def overset(node, style)
    placed = typeset(node.children[0], 'script')
    base = typeset(node.children[1], style)
    width = [placed.width, base.width].max
    box = Box.new(width, placed.height + base.height, placed.height + base.baseline, 'overset')
    box.add(placed, center(placed, width), 0, 'over: ')
    box.add(base, center(base, width), placed.height, 'base: ')
    box
  end

  def underset(node, style)
    placed = typeset(node.children[0], 'script')
    base = typeset(node.children[1], style)
    width = [placed.width, base.width].max
    box = Box.new(width, base.height + placed.height, base.baseline, 'underset')
    box.add(base, center(base, width), 0, 'base: ')
    box.add(placed, center(placed, width), base.height, 'under: ')
    box
  end

  def radical(body, index = nil)
    k = body.height
    extra = index ? [0, index.width - 1].max : 0
    top = index ? [0, index.height - k].max : 0
    box = Box.new(extra + k + 1 + body.width, k + 1 + top, body.baseline + 1 + top, index ? 'root' : 'sqrt')
    box.draw('_' * body.width, extra + k + 1, top)
    box.draw('\\', extra, k + top)
    (1..k).each { |r| box.draw('/', extra + k - r + 1, r + top) }
    if index
      box.add(index, 0, k - index.height + top, 'index: ')
      box.add(body, extra + k + 1, 1 + top, 'body: ')
    else
      box.add(body, k + 1, 1)
    end
    box
  end

  def sqrt(node, style)
    radical(typeset(node.children[0], style))
  end

  def root(node, style)
    radical(typeset(node.children[1], style), typeset(node.children[0], 'script'))
  end

  def delimit(body, left, right)
    wl = left == '.' ? 0 : 1
    wr = right == '.' ? 0 : 1
    box = Box.new(wl + body.width + wr, body.height, body.baseline, "delim #{left} #{right}")
    box.add(body, wl, 0)
    draw_delimiter(box, left, 0, body.height)
    draw_delimiter(box, right, wl + body.width, body.height)
    box
  end

  def delim(node, style)
    delimit(typeset(node.children[0], style), *node.value)
  end

  def matrix(node, style)
    cells = node.children.map { |row| row.map { |cell| typeset(cell, style) } }
    rows, columns = cells.size, cells[0].size
    widths = columns.times.map { |j| cells.map { |row| row[j].width }.max }
    ascents = cells.map { |row| row.map(&:baseline).max }
    descents = cells.map { |row| row.map(&:descent).max }
    heights = rows.times.map { |i| ascents[i] + descents[i] + 1 }
    col_gap, row_gap = @params.values_at('col_gap', 'row_gap')
    body_width = widths.sum + col_gap * (columns - 1)
    body_height = heights.sum + row_gap * (rows - 1)
    environment = node.value
    shift = environment == 'matrix' ? 0 : 2
    extra = environment == 'matrix' ? 0 : (environment == 'cases' ? 2 : 4)
    box = Box.new(body_width + extra, body_height, (body_height - 1) / 2, "#{environment} rows=#{rows} cols=#{columns}")
    y = 0
    cells.each_with_index do |row, i|
      x = shift
      row.each_with_index do |cell, j|
        offset = environment == 'cases' ? 0 : center(cell, widths[j])
        box.add(cell, x + offset, y + ascents[i] - cell.baseline, "cell #{i + 1},#{j + 1}: ")
        x += widths[j] + col_gap
      end
      y += heights[i] + row_gap
    end
    if environment == 'cases'
      draw_delimiter(box, '\\{', 0, body_height)
    elsif environment != 'matrix'
      left, right = { 'pmatrix' => ['(', ')'], 'bmatrix' => ['[', ']'], 'vmatrix' => ['|', '|'] }.fetch(environment)
      draw_delimiter(box, left, 0, body_height)
      draw_delimiter(box, right, body_width + 3, body_height)
    end
    box
  end

  def accent(node, style)
    body = typeset(node.children[0], style)
    name = node.value
    width = body.width
    width = [width, 1].max if %w[hat dot tilde].include?(name)
    width = [width, 2].max if name == 'vec'
    width += 2 if %w[overbrace underbrace].include?(name)
    baseline = name == 'underbrace' ? body.baseline : body.baseline + 1
    box = Box.new(width, body.height + 1, baseline, name)
    if name == 'underbrace'
      box.add(body, 1, 0)
      box.draw('\\' + '-' * body.width + '/', 0, body.height)
    elsif name == 'overbrace'
      box.add(body, 1, 1)
      box.draw('/' + '-' * body.width + '\\')
    else
      box.add(body, 0, 1)
      if name == 'overline'
        box.draw('_' * width)
      elsif name == 'vec'
        box.draw('-' * (width - 1) + '>')
      else
        box.draw({ 'hat' => '^', 'dot' => '.', 'tilde' => '~' }.fetch(name), (width - 1) / 2)
      end
    end
    box
  end
end

def build_lines(breaks, types, boxes, starts, params)
  result = []
  position = 0
  alignment = nil
  while position < boxes.size
    indent = if position.zero?
               0
             elsif alignment.nil?
               params['indent']
             elsif types[position][0] == 'relation'
               alignment[0]
             else
               alignment[0] + alignment[1] + params['rel_space']
             end
    ends = breaks.select { |i| i > position }.sort + [boxes.size]
    candidates = ends.map { |last| [last, starts[last - 1] + boxes[last - 1].width - starts[position]] }
    fitting = candidates.select { |_, width| indent + width <= params['width'] }
    last, width = fitting.empty? ? candidates[0] : fitting[-1]
    result << [position, last, indent, width]
    if position.zero?
      relation = (0...last).find { |i| types[i][0] == 'relation' }
      alignment = [starts[relation], boxes[relation].width] if relation
    end
    position = last
  end
  result
end

def place_formula(formula, typesetter, params)
  nodes = formula.nodes
  types, gaps = Layout.spacing(nodes, 'normal', params)
  boxes = nodes.map { |node| typesetter.typeset(node) }
  starts = []
  x = 0
  boxes.each_with_index { |box, i| starts << x; x += box.width + (gaps[i] || 0) }
  indices = (1...nodes.size).to_a
  relations = indices.select { |i| types[i][0] == 'relation' }
  plus_minus = indices.select { |i| nodes[i].kind == 'symbol' && %w[+ -].include?(nodes[i].value) && types[i][0] == 'binary' }
  punctuation = indices.select { |i| types[i - 1][1] == 'punctuation' }
  plan = nil
  [relations, relations | plus_minus, relations | plus_minus | punctuation].each do |breaks|
    plan = build_lines(breaks, types, boxes, starts, params)
    break if plan.all? { |_, _, indent, width| indent + width <= params['width'] }
  end
  roots, overfull = [], []
  width = height = 0
  plan.each_with_index do |(first, last, indent, line_width), i|
    line = Layout.row(boxes[first...last], gaps[first...(last - 1)], "line #{i + 1}")
    roots << [line, indent, height]
    height += line.height
    width = [width, indent + line.width].max
    overfull << [i + 1, indent + line_width] if indent + line_width > params['width']
  end
  if formula.tag_string
    tag = formula.tag_string
    tx = params['width'] - tag.size
    last, last_x, last_y = roots[-1]
    if tx >= last_x + last.width + 2
      ty = last_y + last.baseline
    else
      ty = height
      height += 1
    end
    tag_box = Box.new(tag.size, 1, 0, "tag \"#{tag}\"")
    tag_box.draw(tag)
    roots << [tag_box, tx, ty]
    width = [width, tx + tag.size].max
  end
  [roots, plan.size, width, height, overfull]
end

def tree_notation(node)
  kind = node.kind
  return node.value if %w[identifier number command].include?(kind)
  return "'#{node.value}'" if kind == 'symbol'
  return "\"#{node.value}\"" if kind == 'text'
  return "(eqref \"#{node.value}\")" if kind == 'reference'
  return '(row' + node.children.map { |child| ' ' + tree_notation(child) }.join + ')' if kind == 'row'
  if kind == 'matrix'
    rows = node.children.map { |row| '[' + row.map { |cell| tree_notation(cell) }.join(' ') + ']' }
    return '(' + node.value + ' ' + rows.join(' ') + ')'
  end
  if kind == 'delim'
    delimiters = node.value.map { |value| value.size == 1 ? "'#{value}'" : value }
    return '(delim ' + delimiters.join(' ') + ' ' + tree_notation(node.children[0]) + ')'
  end
  if kind == 'script'
    _, sub, sup = node.children
    name = sub.nil? ? 'sup' : (sup.nil? ? 'sub' : 'subsup')
    children = node.children.compact
  else
    name = kind == 'accent' ? node.value : kind
    children = node.children
  end
  '(' + name + ' ' + children.map { |child| tree_notation(child) }.join(' ') + ')'
end

class LinearNotation
  def initialize(params, references)
    @params, @references = params, references
  end

  def row(nodes, style = 'normal')
    _, gaps = Layout.spacing(nodes, style, @params)
    nodes.each_with_index.map { |node, i| (i.zero? ? '' : ' ' * gaps[i - 1]) + notation(node, style) }.join
  end

  def parenthesize(node, style, kinds)
    value = notation(node, style)
    kinds.include?(node.kind) ? '(' + value + ')' : value
  end

  def notation(node, style = 'normal')
    kind = node.kind
    return node.value if %w[identifier number symbol text].include?(kind)
    return Boxes::DISPLAY.fetch(node.value) if kind == 'command'
    return @references.fetch(node.value, '(??)') if kind == 'reference'
    return row(node.children, style) if kind == 'row'
    if kind == 'frac'
      return node.children.map { |child| parenthesize(child, style, %w[row frac]) }.join('/')
    end
    if kind == 'script'
      base, sub, sup = node.children
      value = parenthesize(base, style, %w[row frac script])
      value += '_' + parenthesize(sub, 'script', %w[row frac]) if sub
      value += '^' + parenthesize(sup, 'script', %w[row frac]) if sup
      return value
    end
    if kind == 'delim'
      left, right = node.value.map { |d| d == '.' ? '' : d[-1] }
      return left + notation(node.children[0], style) + right
    end
    if kind == 'matrix'
      rows = node.children.map { |row| row.map { |cell| notation(cell, style) }.join(', ') }
      return node.value + '[' + rows.join('; ') + ']'
    end
    if %w[root overset underset].include?(kind)
      return kind + '(' + notation(node.children[0], 'script') + ', ' + notation(node.children[1], style) + ')'
    end
    name = kind == 'accent' ? node.value : kind
    name + '(' + node.children.map { |child| notation(child, style) }.join(', ') + ')'
  end
end

def diagnostic(formula, column, message, warning = false)
  ["formula #{formula.number}, column #{column}: #{warning ? 'warning: ' : ''}#{message}",
   '  ' + formula.line, ' ' * (column + 1) + '^']
end

def main
  params = File.readlines('input/params.txt', chomp: true).to_h do |line|
    name, value = line.split(' ')
    [name, value.to_i]
  end
  formulas = File.readlines('input/formulas.txt', chomp: true).each_with_index.map { |line, i| Formula.new(i + 1, line) }
  references = reference_table(formulas)
  typesetter, linear = Typesetter.new(params, references), LinearNotation.new(params, references)
  rendered, boxes, trees, errors = [], [], [], []
  kinds = Hash.new(0)
  total_boxes = max_depth = valid = error_count = warnings = overfull_count = 0
  formulas.each_with_index do |formula, index|
    rendered << '' if index.positive?
    rendered << "formula #{formula.number}"
    if formula.error
      error_count += 1
      rendered << '(error)'
      boxes << "formula #{formula.number}: error"
      trees << "formula #{formula.number}: error"
      errors.concat(diagnostic(formula, *formula.error))
      next
    end
    valid += 1
    collect_warnings(formula, references)
    roots, lines, width, height, overfull = place_formula(formula, typesetter, params)
    rendered.concat(Canvas.draw(roots, width, height))
    entries = Canvas.box_lines(roots)
    depth = entries.map { |_, level, _| level }.max + 1
    total_boxes += entries.size
    max_depth = [max_depth, depth].max
    boxes << "formula #{formula.number}: lines=#{lines} width=#{width} height=#{height} boxes=#{entries.size} depth=#{depth}"
    entries.each { |line, _, kind| boxes << line; kinds[kind] += 1 }
    trees << "formula #{formula.number}: " + formula.nodes.map { |node| tree_notation(node) }.join(' ')
    notation = linear.row(formula.nodes).rstrip
    trees << '  linear:' + (notation.empty? ? '' : ' ' + notation)
    trees << '  tag: ' + formula.tag_string if formula.tag_string
    warnings += formula.warnings.size
    formula.warnings.each { |column, message| errors.concat(diagnostic(formula, column, message, true)) }
    overfull_count += overfull.size
    overfull.each { |number, occupied| errors << "formula #{formula.number}: line #{number} is overfull (width #{occupied} > #{params['width']})" }
  end
  boxes << "summary: boxes=#{total_boxes} max_depth=#{max_depth}"
  kinds.keys.sort.each { |kind| boxes << "  #{kind}: #{kinds[kind]}" }
  errors << "formulas=#{formulas.size} rendered=#{valid} errors=#{error_count} warnings=#{warnings} overfull=#{overfull_count}"
  FileUtils.mkdir_p('output')
  { 'rendered.txt' => rendered, 'boxes.txt' => boxes, 'trees.txt' => trees, 'errors.txt' => errors }.each do |name, lines|
    File.write(File.join('output', name), lines.join("\n") + "\n")
  end
end

main if $PROGRAM_NAME == __FILE__
