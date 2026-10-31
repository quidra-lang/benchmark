class Element
  attr_accessor :type, :id, :classes, :text, :parent, :depth, :children,
                :overrides, :style, :margin, :padding, :border, :displayed,
                :cw, :ch, :natural, :rx, :ry, :x, :y, :lines, :maximum,
                :contribution, :containing

  def initialize(type, id, classes, text, parent, depth)
    @type, @id, @classes, @text, @parent, @depth = type, id, classes, text, parent, depth
    @children = []
    @overrides = {}
  end

  def frame(horizontal)
    sides = horizontal ? [1, 3] : [0, 2]
    sides.sum { |i| @padding[i] + @border[i] }
  end

  def margins(horizontal)
    (horizontal ? [1, 3] : [0, 2]).sum { |i| @margin[i] }
  end

  def width
    @cw + frame(true)
  end

  def height
    @ch + frame(false)
  end
end

class BoxLayout
  SIDES = %w[top right bottom left].freeze
  DEFAULTS = {
    'display' => 'block', 'position' => 'static', 'box-sizing' => 'content-box',
    'width' => 'auto', 'height' => 'auto', 'min-width' => '0', 'min-height' => '0',
    'max-width' => 'none', 'max-height' => 'none', 'top' => 'auto', 'right' => 'auto',
    'bottom' => 'auto', 'left' => 'auto', 'flex-direction' => 'row', 'flex-wrap' => 'nowrap',
    'justify-content' => 'start', 'align-items' => 'stretch', 'align-self' => 'auto',
    'row-gap' => '0', 'column-gap' => '0', 'order' => '0', 'flex-grow' => '0',
    'flex-shrink' => '1', 'flex-basis' => 'auto', 'grid-template-columns' => 'none',
    'grid-template-rows' => 'none', 'grid-column' => 'auto', 'grid-row' => 'auto'
  }.merge(%w[margin padding border].product(SIDES).to_h { |prefix, side| ["#{prefix}-#{side}", '0'] }).freeze
  CHOICES = {
    'display' => %w[block flex grid none], 'position' => %w[static relative absolute],
    'box-sizing' => %w[content-box border-box], 'flex-direction' => %w[row row-reverse column column-reverse],
    'flex-wrap' => %w[nowrap wrap], 'justify-content' => %w[start end center space-between space-around space-evenly],
    'align-items' => %w[stretch start end center], 'align-self' => %w[auto stretch start end center]
  }.freeze

  def initialize(width, height, rules, elements)
    @width, @height, @rules, @elements = width, height, rules, elements
    @ids = elements.to_h { |e| [e.id, e] }
    relayout
  end

  def self.integer?(text)
    /\A[0-9]{1,3}\z/.match?(text)
  end

  def self.positive?(text)
    integer?(text) && text.to_i.positive?
  end

  def self.signed?(text)
    integer?(text) || (text.start_with?('-') && integer?(text[1..]))
  end

  def self.percentage?(text)
    text.end_with?('%') && integer?(text[0...-1])
  end

  def self.fraction?(text)
    text.end_with?('fr') && positive?(text[0...-2])
  end

  def self.known?(property)
    DEFAULTS.key?(property) || %w[margin padding border gap].include?(property)
  end

  def self.declaration(property, value)
    return nil unless known?(property)
    tokens = value.split(' ')
    if %w[margin padding border].include?(property)
      return nil unless (1..4).cover?(tokens.length) && tokens.all? { |t| property == 'border' ? %w[0 1].include?(t) : integer?(t) }
      a, b, c, d = tokens
      return SIDES.zip([a, b || a, c || a, d || b || a]).map { |side, v| ["#{property}-#{side}", v] }
    end
    if property == 'gap'
      return nil unless (1..2).cover?(tokens.length) && tokens.all? { |t| integer?(t) }
      return [['row-gap', tokens[0]], ['column-gap', tokens[-1]]]
    end
    if %w[grid-template-columns grid-template-rows].include?(property)
      valid = value == 'none' || tokens.all? { |t| t == 'auto' || integer?(t) || fraction?(t) }
    elsif %w[grid-column grid-row].include?(property)
      valid = value == 'auto' || (tokens.length == 1 && positive?(tokens[0])) ||
              (tokens.length == 2 && tokens[0] == 'span' && positive?(tokens[1])) ||
              (tokens.length == 3 && positive?(tokens[0]) && tokens[1] == '/' && positive?(tokens[2]) && tokens[0].to_i < tokens[2].to_i) ||
              (tokens.length == 4 && positive?(tokens[0]) && tokens[1] == '/' && tokens[2] == 'span' && positive?(tokens[3]))
    elsif tokens.length == 1
      valid = if CHOICES.key?(property)
                CHOICES[property].include?(value)
              elsif %w[width height flex-basis].include?(property)
                value == 'auto' || integer?(value) || percentage?(value)
              elsif %w[min-width min-height].include?(property)
                integer?(value) || percentage?(value)
              elsif %w[max-width max-height].include?(property)
                value == 'none' || integer?(value) || percentage?(value)
              elsif %w[top right bottom left].include?(property)
                value == 'auto' || signed?(value)
              elsif property == 'order'
                signed?(value)
              elsif property.start_with?('border-')
                %w[0 1].include?(value)
              else
                integer?(value)
              end
    end
    valid ? [[property, value]] : nil
  end

  def children(element, ordered = false)
    result = element.children.select { |e| e.displayed && e.style['position'] != 'absolute' }
    ordered ? result.sort_by { |e| [e.style['order'].to_i, @elements.index(e)] } : result
  end

  def align(parent, child)
    child.style['align-self'] == 'auto' ? parent.style['align-items'] : child.style['align-self']
  end

  def resolve(element, property, reference, horizontal)
    value = element.style[property]
    return nil if %w[auto none].include?(value) || (value.end_with?('%') && reference.nil?)
    result = value.end_with?('%') ? reference * value.to_i / 100 : value.to_i
    element.style['box-sizing'] == 'border-box' ? [0, result - element.frame(horizontal)].max : result
  end

  def clamp(element, value, reference, horizontal)
    axis = horizontal ? 'width' : 'height'
    lower = resolve(element, 'min-' + axis, reference, horizontal) || 0
    upper = resolve(element, 'max-' + axis, reference, horizontal)
    value = [value, upper].min if upper
    [value, lower].max
  end

  def distribute(total, weights)
    sum = weights.sum
    return Array.new(weights.length, 0) if sum.zero?
    result = weights.map { |weight| total * weight / sum }
    remainder = total - result.sum
    weights.each_index do |i|
      break if remainder.zero?
      if weights[i].positive?
        result[i] += 1
        remainder -= 1
      end
    end
    result
  end

  def grid_position(value)
    tokens = value.split(' ')
    return [0, 1] if value == 'auto'
    return [0, tokens[1].to_i] if tokens[0] == 'span'
    start = tokens[0].to_i
    [start, tokens.length == 1 ? 1 : tokens[2] == 'span' ? tokens[3].to_i : tokens[2].to_i - start]
  end

  def placement(element)
    columns = element.style['grid-template-columns'] == 'none' ? ['auto'] : element.style['grid-template-columns'].split(' ')
    rows = element.style['grid-template-rows'] == 'none' ? [] : element.style['grid-template-rows'].split(' ')
    items = children(element, true).map do |child|
      column, cs = grid_position(child.style['grid-column'])
      row, rs = grid_position(child.style['grid-row'])
      { element: child, column: column, row: row, cs: cs, rs: rs }
    end
    nc = ([columns.length] + items.map { |i| i[:column].zero? ? i[:cs] : i[:column] + i[:cs] - 1 }).max
    occupied = {}
    overlaps = lambda do |item, row, column|
      (row...(row + item[:rs])).any? { |r| (column...(column + item[:cs])).any? { |c| occupied[[r, c]] } }
    end
    occupy = lambda do |item|
      (item[:row]...(item[:row] + item[:rs])).each { |r| (item[:column]...(item[:column] + item[:cs])).each { |c| occupied[[r, c]] = true } }
    end
    items.each { |item| occupy.call(item) if item[:row].positive? && item[:column].positive? }
    cr = cc = 1
    items.each do |item|
      next if item[:row].positive? && item[:column].positive?
      if item[:row].positive?
        column = (1..(nc - item[:cs] + 1)).find { |c| !overlaps.call(item, item[:row], c) }
        item[:column] = column || 1
      elsif item[:column].positive?
        cr += 1 if item[:column] < cc
        row = cr
        row += 1 while overlaps.call(item, row, item[:column])
        item[:row] = cr = row
        cc = item[:column] + item[:cs]
      else
        row, column = cr, cc
        loop do
          if column + item[:cs] - 1 > nc
            row += 1
            column = 1
          elsif overlaps.call(item, row, column)
            column += 1
          else
            break
          end
        end
        item[:row], item[:column] = row, column
        cr, cc = row, column + item[:cs]
      end
      occupy.call(item)
    end
    nr = ([rows.length] + items.map { |i| i[:row] + i[:rs] - 1 }).max
    { items: items, columns: columns + Array.new(nc - columns.length, 'auto'), rows: rows + Array.new(nr - rows.length, 'auto') }
  end

  def track_sizes(grid, horizontal, available, gap, contributions)
    specifications = grid[horizontal ? :columns : :rows]
    fractional = specifications.any? { |t| self.class.fraction?(t) }
    weights = []
    sizes = specifications.each_with_index.map do |specification, i|
      weights << (fractional ? (self.class.fraction?(specification) ? specification.to_i : 0) : (specification == 'auto' ? 1 : 0))
      if self.class.integer?(specification)
        specification.to_i
      elsif specification == 'auto' || available.nil?
        grid[:items].each_index.select { |j| grid[:items][j][horizontal ? :column : :row] == i + 1 && grid[:items][j][horizontal ? :cs : :rs] == 1 }.map { |j| contributions[j] }.max || 0
      else
        0
      end
    end
    if available
      leftover = available - sizes.sum - gap * (sizes.length - 1)
      additions = distribute([leftover, 0].max, weights)
      sizes = sizes.zip(additions).map(&:sum)
    end
    sizes
  end

  def max_content(element)
    return element.maximum unless element.maximum.nil?
    items = children(element)
    value = if element.text
              element.text.length
            elsif element.style['display'] == 'flex' && element.style['flex-direction'].start_with?('row')
              items.empty? ? 0 : items.sum { |e| contribution(e) } + element.style['column-gap'].to_i * (items.length - 1)
            elsif element.style['display'] == 'grid'
              grid = placement(element)
              track_sizes(grid, true, nil, element.style['column-gap'].to_i, grid[:items].map { |i| contribution(i[:element]) }).sum + element.style['column-gap'].to_i * (grid[:columns].length - 1)
            else
              items.map { |e| contribution(e) }.max || 0
            end
    element.maximum = value
  end

  def contribution(element)
    element.contribution ||= clamp(element, resolve(element, 'width', nil, true) || max_content(element), nil, true) + element.frame(true) + element.margins(true)
  end

  def position_child(parent, child, x, y)
    child.rx = parent.border[3] + parent.padding[3] + x
    child.ry = parent.border[0] + parent.padding[0] + y
  end

  def layout(element, cw_reference, ch_reference, fw = nil, fh = nil)
    element.cw = fw || clamp(element, resolve(element, 'width', cw_reference, true) || [0, cw_reference - element.frame(true) - element.margins(true)].max, cw_reference, true)
    unless fh
      height = resolve(element, 'height', ch_reference, false)
      fh = clamp(element, height, ch_reference, false) if height
    end
    if element.text
      element.lines = []
      element.text.split(' ').each do |word|
        if !element.lines.empty? && element.lines.last.length + 1 + word.length <= element.cw
          element.lines[-1] += ' ' + word
        else
          element.lines << word
        end
      end
      natural = element.lines.length
    else
      natural = case element.style['display']
                when 'flex' then flex(element, fh, ch_reference)
                when 'grid' then grid_layout(element, fh)
                else block(element, fh)
                end
    end
    element.natural = natural
    element.ch = fh || clamp(element, natural, ch_reference, false)
    natural
  end

  def block(element, reference)
    bottom = 0
    previous = nil
    children(element).each do |child|
      layout(child, element.cw, reference)
      y = bottom + (previous ? [previous.margin[2], child.margin[0]].max : child.margin[0])
      position_child(element, child, child.margin[3], y)
      bottom = y + child.height
      previous = child
    end
    previous ? bottom + previous.margin[2] : 0
  end

  def flex(element, reference, height_reference)
    horizontal = element.style['flex-direction'].start_with?('row')
    reverse = element.style['flex-direction'].end_with?('reverse')
    main_reference = horizontal ? element.cw : reference
    gap = element.style[horizontal ? 'column-gap' : 'row-gap'].to_i
    line_gap = element.style['row-gap'].to_i
    items = children(element, true).map do |child|
      alignment = align(element, child)
      cross = nil
      unless horizontal
        room = [0, element.cw - child.frame(true) - child.margins(true)].max
        cross = resolve(child, 'width', element.cw, true)
        cross ||= alignment == 'stretch' ? room : [max_content(child), room].min
        cross = clamp(child, cross, element.cw, true)
      end
      base = resolve(child, 'flex-basis', main_reference, horizontal) || resolve(child, horizontal ? 'width' : 'height', main_reference, horizontal)
      base ||= horizontal ? max_content(child) : layout(child, element.cw, reference, cross)
      hypothetical = clamp(child, base, main_reference, horizontal)
      { element: child, align: alignment, cross: cross, base: base, hypothetical: hypothetical, outer: child.frame(horizontal) + child.margins(horizontal) }
    end
    main_length = if horizontal
                    element.cw
                  elsif reference
                    reference
                  else
                    clamp(element, items.sum { |i| i[:hypothetical] + i[:outer] } + gap * [items.length - 1, 0].max, height_reference, false)
                  end
    lines = []
    items.each do |item|
      current = lines.last
      if current.nil? || (horizontal && element.style['flex-wrap'] == 'wrap' && current.sum { |i| i[:hypothetical] + i[:outer] } + gap * current.length + item[:hypothetical] + item[:outer] > main_length)
        lines << []
      end
      lines.last << item
    end
    cross_start = 0
    lines.each do |line|
      total_gap = gap * (line.length - 1)
      growing = line.sum { |i| i[:hypothetical] + i[:outer] } + total_gap < main_length
      line.each do |item|
        child = item[:element]
        item[:weight] = growing ? child.style['flex-grow'].to_i : child.style['flex-shrink'].to_i * item[:base]
        item[:size] = item[:hypothetical]
        item[:frozen] = item[:weight].zero? || (growing ? item[:base] > item[:hypothetical] : item[:base] < item[:hypothetical])
      end
      until line.all? { |i| i[:frozen] }
        free = main_length - total_gap - line.sum { |i| (i[:frozen] ? i[:size] : i[:base]) + i[:outer] }
        active = line.reject { |i| i[:frozen] }
        assigned = distribute([growing ? free : -free, 0].max, active.map { |i| i[:weight] })
        active.each_with_index do |item, i|
          tentative = item[:base] + (growing ? assigned[i] : -assigned[i])
          item[:size] = clamp(item[:element], tentative, main_reference, horizontal)
          item[:violation] = item[:size] - tentative
        end
        violation = active.sum { |i| i[:violation] }
        active.each { |i| i[:frozen] = true if violation.zero? || (violation.positive? ? i[:violation].positive? : i[:violation].negative?) }
      end
      if horizontal
        line.each do |item|
          layout(item[:element], element.cw, reference, item[:size])
          item[:cross] = item[:element].ch
        end
      end
      outer_cross = line.map { |i| i[:cross] + i[:element].frame(!horizontal) + i[:element].margins(!horizontal) }.max || 0
      line_cross = if !horizontal
                     element.cw
                   elsif lines.length == 1
                     reference || clamp(element, outer_cross, height_reference, false)
                   else
                     outer_cross
                   end
      remaining = main_length - total_gap - line.sum { |i| i[:size] + i[:outer] }
      spaces = Array.new(line.length, 0)
      if remaining.positive?
        case element.style['justify-content']
        when 'end' then spaces[0] = remaining
        when 'center' then spaces[0] = remaining / 2
        when 'space-between', 'space-around', 'space-evenly'
          kind = element.style['justify-content']
          weights = Array.new(line.length + 1) { |i| kind == 'space-evenly' ? 1 : i.zero? || i == line.length ? (kind == 'space-between' ? 0 : 1) : (kind == 'space-between' ? 1 : 2) }
          spaces = distribute(remaining, weights).take(line.length)
        end
      end
      cursor = 0
      line.each_with_index do |item, i|
        child = item[:element]
        cross = item[:cross]
        if horizontal
          if item[:align] == 'stretch' && child.style['height'] == 'auto'
            cross = clamp(child, [0, line_cross - child.frame(false) - child.margins(false)].max, reference, false)
            layout(child, element.cw, reference, item[:size], cross)
          else
            layout(child, element.cw, reference, item[:size])
          end
        else
          layout(child, element.cw, reference, cross, item[:size])
        end
        room = line_cross - cross - child.frame(!horizontal) - child.margins(!horizontal)
        offset = room.positive? ? (item[:align] == 'end' ? room : item[:align] == 'center' ? room / 2 : 0) : 0
        cursor += spaces[i]
        size = item[:size] + item[:outer]
        main = reverse ? main_length - cursor - size + child.margin[horizontal ? 3 : 0] : cursor + child.margin[horizontal ? 3 : 0]
        cross_position = cross_start + offset + child.margin[horizontal ? 0 : 3]
        position_child(element, child, horizontal ? main : cross_position, horizontal ? cross_position : main)
        cursor += size + gap
      end
      cross_start += line_cross + line_gap
    end
    horizontal ? (lines.empty? ? 0 : cross_start - line_gap) : main_length
  end

  def grid_layout(element, reference)
    grid = placement(element)
    column_gap = element.style['column-gap'].to_i
    row_gap = element.style['row-gap'].to_i
    columns = track_sizes(grid, true, element.cw, column_gap, grid[:items].map { |i| contribution(i[:element]) })
    grid[:items].each do |item|
      child = item[:element]
      start = item[:column] - 1
      item[:aw] = columns[start, item[:cs]].sum + column_gap * (item[:cs] - 1)
      item[:ax] = columns.take(start).sum + column_gap * start
      item[:gw] = clamp(child, resolve(child, 'width', item[:aw], true) || [0, item[:aw] - child.frame(true) - child.margins(true)].max, item[:aw], true)
      layout(child, item[:aw], nil, item[:gw])
      item[:row_contribution] = child.height + child.margins(false)
    end
    rows = track_sizes(grid, false, reference, row_gap, grid[:items].map { |i| i[:row_contribution] })
    grid[:items].each do |item|
      child = item[:element]
      start = item[:row] - 1
      area_height = rows[start, item[:rs]].sum + row_gap * (item[:rs] - 1)
      area_y = rows.take(start).sum + row_gap * start
      alignment = align(element, child)
      height = alignment == 'stretch' && child.style['height'] == 'auto' ? clamp(child, [0, area_height - child.frame(false) - child.margins(false)].max, area_height, false) : nil
      layout(child, item[:aw], area_height, item[:gw], height)
      room = area_height - child.height - child.margins(false)
      offset = room.positive? ? (alignment == 'end' ? room : alignment == 'center' ? room / 2 : 0) : 0
      position_child(element, child, item[:ax] + child.margin[3], area_y + offset + child.margin[0])
    end
    rows.empty? ? 0 : rows.sum + row_gap * (rows.length - 1)
  end

  def relayout
    @elements.each do |element|
      element.style = DEFAULTS.dup
      priorities = {}
      @rules.each do |selectors, declarations|
        matches = selectors.filter_map do |selector|
          selector.start_with?('#') ? (selector[1..] == element.id ? 2 : nil) : selector.start_with?('.') ? (element.classes.include?(selector[1..]) ? 1 : nil) : (selector == element.type ? 0 : nil)
        end
        next if matches.empty?
        specificity = matches.max
        declarations.each do |property, value|
          if !priorities.key?(property) || specificity >= priorities[property]
            element.style[property] = value
            priorities[property] = specificity
          end
        end
      end
      element.style.merge!(element.overrides)
      element.margin, element.padding, element.border = %w[margin padding border].map { |prefix| SIDES.map { |side| element.style["#{prefix}-#{side}"].to_i } }
      element.displayed = element.style['display'] != 'none' && (!element.parent || element.parent.displayed)
      element.maximum = element.contribution = nil
      element.lines = []
      element.containing = nil
    end
    root = @elements.first
    if root.displayed && root.style['position'] != 'absolute'
      layout(root, @width, @height)
      root.rx, root.ry = root.margin[3], root.margin[0]
    end
    @elements.each do |element|
      next unless element.displayed && element.style['position'] == 'absolute'
      ancestor = element.parent
      ancestor = ancestor.parent while ancestor && ancestor.style['position'] == 'static'
      element.containing = ancestor
      cbw = ancestor ? ancestor.cw + ancestor.padding[1] + ancestor.padding[3] : @width
      cbh = ancestor ? ancestor.ch + ancestor.padding[0] + ancestor.padding[2] : @height
      offsets = %w[left right top bottom].map { |p| element.style[p] == 'auto' ? nil : element.style[p].to_i }
      left, right, top, bottom = offsets
      width = resolve(element, 'width', cbw, true)
      unless width
        room = [0, cbw - (left || 0) - (right || 0) - element.margins(true) - element.frame(true)].max
        width = left && right ? room : [max_content(element), room].min
      end
      fw = clamp(element, width, cbw, true)
      fh = element.style['height'] == 'auto' && top && bottom ? clamp(element, [0, cbh - top - bottom - element.margins(false) - element.frame(false)].max, cbh, false) : nil
      layout(element, cbw, cbh, fw, fh)
      element.rx = left ? left + element.margin[3] : right ? cbw - right - element.margin[1] - element.width : element.margin[3]
      element.ry = top ? top + element.margin[0] : bottom ? cbh - bottom - element.margin[2] - element.height : element.margin[0]
    end
    @elements.each do |element|
      next unless element.displayed
      reference = element.style['position'] == 'absolute' ? element.containing : element.parent
      x = reference ? reference.x : 0
      y = reference ? reference.y : 0
      if element.style['position'] == 'absolute' && reference
        x += reference.border[3]
        y += reference.border[0]
      end
      element.x, element.y = x + element.rx, y + element.ry
      if element.style['position'] == 'relative'
        left, right, top, bottom = %w[left right top bottom].map { |p| element.style[p] == 'auto' ? nil : element.style[p].to_i }
        element.x += left || (right ? -right : 0)
        element.y += top || (bottom ? -bottom : 0)
      end
    end
  end

  def boxes(element)
    x, y, w, h = element.x, element.y, element.width, element.height
    m, b, p = element.margin, element.border, element.padding
    [[x - m[3], y - m[0], w + m[1] + m[3], h + m[0] + m[2]], [x, y, w, h],
     [x + b[3], y + b[0], w - b[1] - b[3], h - b[0] - b[2]],
     [x + b[3] + p[3], y + b[0] + p[0], element.cw, element.ch]]
  end

  def snapshot
    @elements.map { |e| e.displayed ? [e.x, e.y, e.width, e.height] : nil }
  end

  def changes(before)
    changed = @elements.each_index.select { |i| before[i] != snapshot[i] }.map { |i| @elements[i].id }
    changed.empty? ? 'no change' : changed.join(' ')
  end

  def render
    screen = Array.new(@height) { '.' * @width }
    @elements.each do |element|
      next unless element.displayed
      x, y, w, h = boxes(element)[1]
      ([y, 0].max...[y + h, @height].min).each do |row|
        ([x, 0].max...[x + w, @width].min).each do |column|
          horizontal = (element.border[0] == 1 && row == y) || (element.border[2] == 1 && row == y + h - 1)
          vertical = (element.border[3] == 1 && column == x) || (element.border[1] == 1 && column == x + w - 1)
          screen[row][column] = horizontal && vertical ? '+' : horizontal ? '-' : vertical ? '|' : ' '
        end
      end
      next unless element.text
      cx, cy = boxes(element)[3].take(2)
      element.lines.each_with_index do |line, i|
        row = cy + i
        next unless (0...@height).cover?(row)
        line.each_char.with_index { |char, j| screen[row][cx + j] = char if (0...@width).cover?(cx + j) }
      end
    end
    puts "render #{@width}x#{@height}", '#' * (@width + 2)
    screen.each { |row| puts '#' + row + '#' }
    puts '#' * (@width + 2)
  end

  def execute(line)
    command, *args = line.split(' ')
    case command
    when 'LAYOUT'
      puts "layout #{@width}x#{@height}"
      @elements.each { |e| puts '  ' * e.depth + e.id + (e.displayed ? " #{e.x} #{e.y} #{e.width} #{e.height}" : ' none') }
    when 'BOX'
      element = @ids[args[0]]
      if !element
        puts "error: unknown element #{args[0]}"
      elsif !element.displayed
        puts "box #{element.id}: none"
      else
        puts "box #{element.id}"
        %w[margin border padding content].zip(boxes(element)).each { |name, rect| puts name + ' ' + rect.join(' ') }
      end
    when 'RENDER'
      render
    when 'HIT'
      x, y = args.map(&:to_i)
      if x >= @width || y >= @height
        puts "error: point #{x} #{y} outside viewport"
      else
        element = @elements.reverse.find { |e| e.displayed && e.x <= x && x < e.x + e.width && e.y <= y && y < e.y + e.height }
        path = []
        while element
          path.unshift(element.id)
          element = element.parent
        end
        puts "hit #{x} #{y}: #{path.empty? ? 'none' : path.join(' > ')}"
      end
    when 'SET'
      id, property = args.take(2)
      value = args.drop(2).join(' ')
      if !@ids.key?(id)
        puts "error: unknown element #{id}"
      elsif !self.class.known?(property)
        puts "error: unknown property #{property}"
      elsif !(declarations = self.class.declaration(property, value))
        puts "error: invalid value for #{property}: #{value}"
      else
        before = snapshot
        declarations.each { |p, v| @ids[id].overrides[p] = v }
        relayout
        puts "set #{id} #{property} #{value}: #{changes(before)}"
      end
    when 'VIEWPORT'
      width, height = args.map(&:to_i)
      if !(1..80).cover?(width) || !(1..40).cover?(height)
        puts "error: invalid viewport #{width} #{height}"
      else
        before = snapshot
        @width, @height = width, height
        relayout
        puts "viewport #{width} #{height}: #{changes(before)}"
      end
    when 'OVERFLOW'
      overflow = @elements.select do |e|
        next false unless e.displayed
        if e.text
          e.lines.map(&:length).max > e.cw || e.lines.length > e.ch
        else
          cx, cy, cw, ch = boxes(e)[3]
          children(e).any? do |child|
            x, y, w, h = boxes(child)[0]
            x < cx || y < cy || x + w > cx + cw || y + h > cy + ch
          end
        end
      end.map(&:id)
      puts 'overflow: ' + (overflow.empty? ? 'none' : overflow.join(' '))
    else
      puts "error: unknown command #{command}"
    end
  end
end

input = STDIN.each_line.map(&:chomp)
width, height = input.shift.split(' ').map(&:to_i)
rules = []
until input.first == '---'
  selectors, body = input.shift.split(' { ', 2)
  declarations = body.delete_suffix(' }').split('; ').flat_map do |text|
    property, value = text.split(': ', 2)
    BoxLayout.declaration(property, value) || []
  end
  rules << [selectors.split(', '), declarations]
end
input.shift
elements = []
stack = []
until input.first == '==='
  line = input.shift
  depth = line[/\A */].length / 2
  head, text = line.lstrip.split(' ', 2)
  type, rest = head.split('#', 2)
  id, *classes = rest.split('.')
  parent = depth.zero? ? nil : stack[depth - 1]
  element = Element.new(type, id, classes, text ? text[1...-1] : nil, parent, depth)
  parent.children << element if parent
  elements << element
  stack[depth] = element
end
input.shift
layout = BoxLayout.new(width, height, rules, elements)
input.each do |line|
  break if line == 'END'
  layout.execute(line)
end
