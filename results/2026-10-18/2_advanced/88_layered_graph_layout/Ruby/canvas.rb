require 'set'

class Canvas
  attr_reader :rows, :columns

  def initialize(direction, main, secondary)
    @direction, @main = direction, main
    @vertical = %w[TB BT].include?(direction)
    @rows, @columns = @vertical ? [main, secondary] : [secondary, main]
    @lines = Hash.new(0)
    @arrows, @boxes, @highlights = {}, {}, Set.new
  end

  def cell(main, secondary)
    main = @main - 1 - main if %w[BT RL].include?(@direction)
    @vertical ? [main, secondary] : [secondary, main]
  end

  def add_line(main, secondary, character)
    @lines[cell(main, secondary)] |= { '|' => 1, '-' => 2, '+' => 4 }.fetch(character)
  end

  def main_line(first, last, secondary)
    (first..last).each { |m| add_line(m, secondary, @vertical ? '|' : '-') }
  end

  def segment(start, gap, first, second, offset)
    if first == second
      main_line(start, start + gap - 1, first)
      return
    end
    main_line(start, start + offset - 1, first)
    add_line(start + offset, first, '+')
    add_line(start + offset, second, '+')
    (([first, second].min + 1)...[first, second].max).each do |c|
      add_line(start + offset, c, @vertical ? '-' : '|')
    end
    main_line(start + offset + 1, start + gap - 1, second)
  end

  def arrow(point, reversed)
    forward = { 'TB' => 'v', 'BT' => '^', 'LR' => '>', 'RL' => '<' }
    backward = { 'TB' => '^', 'BT' => 'v', 'LR' => '<', 'RL' => '>' }
    @arrows[cell(*point)] = (reversed ? backward : forward).fetch(@direction)
  end

  def highlight(route)
    route.each_cons(2) do |(r1, c1), (r2, c2)|
      dr, dc = r2 <=> r1, c2 <=> c1
      (0..((r2 - r1).abs + (c2 - c1).abs)).each { |s| @highlights << [r1 + s * dr, c1 + s * dc] }
    end
  end

  def box(label, band, x, left, path)
    text = path ? "{#{label}}" : "[#{label}]"
    row, column = if @vertical
                    cell(band, x - left)
                  elsif @direction == 'LR'
                    [x, band]
                  else
                    [x, @main - band - text.size]
                  end
    text.each_char.with_index { |ch, i| @boxes[[row, column + i]] = ch }
  end

  def crossing_cells
    @lines.values.count { |bits| bits & 3 == 3 }
  end

  def character(row, column)
    point = [row, column]
    @boxes[point] || @arrows[point] || (@highlights.include?(point) ? '#' : nil) ||
      { 0 => ' ', 1 => '|', 2 => '-', 4 => '+' }.fetch(@lines[point], '+')
  end

  def drawing
    ["    #{(0...@columns).map { |c| c % 10 }.join}"] + @rows.times.map do |r|
      (format('%3d ', r) + @columns.times.map { |c| character(r, c) }.join).rstrip
    end
  end
end
