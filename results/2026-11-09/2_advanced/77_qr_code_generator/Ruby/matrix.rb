module QRMatrix
  DATA, FUNCTION, FORMAT, VERSION = 0, 1, 2, 3

  def self.polynomial_remainder(value, divisor)
    while value.bit_length >= divisor.bit_length
      value ^= divisor << (value.bit_length - divisor.bit_length)
    end
    value
  end

  def self.format_information(level, mask)
    indicator = { 'L' => 1, 'M' => 0, 'Q' => 3, 'H' => 2 }.fetch(level)
    shifted = (8 * indicator + mask) << 10
    (shifted + polynomial_remainder(shifted, 0x537)) ^ 0x5412
  end

  def self.version_information(version)
    shifted = version << 12
    shifted + polynomial_remainder(shifted, 0x1f25)
  end

  def self.format_positions(size)
    first = (0...6).map { |i| [8, i] } + [[8, 7], [8, 8], [7, 8]] + (9...15).map { |i| [14 - i, 8] }
    second = (0...8).map { |i| [size - 1 - i, 8] } + (8...15).map { |i| [8, size - 15 + i] }
    [first, second]
  end

  def self.version_positions(size)
    [(0...18).map { |i| [size - 11 + i % 3, i / 3] },
     (0...18).map { |i| [i / 3, size - 11 + i % 3] }]
  end

  def self.write_value(symbol, positions, value)
    positions.each_with_index { |(x, y), i| symbol[y][x] = (value >> i) & 1 }
  end

  def self.read_value(symbol, positions)
    positions.each_with_index.reduce(0) { |value, ((x, y), i)| value | (symbol[y][x] << i) }
  end

  def self.function_matrix(version, alignments)
    size = 17 + 4 * version
    symbol = Array.new(size) { Array.new(size, 0) }
    areas = Array.new(size) { Array.new(size, DATA) }
    [[3, 3], [size - 4, 3], [3, size - 4]].each do |cx, cy|
      (-4..4).each do |dy|
        (-4..4).each do |dx|
          x, y = cx + dx, cy + dy
          next unless x.between?(0, size - 1) && y.between?(0, size - 1)
          symbol[y][x] = [0, 1, 3].include?([dx.abs, dy.abs].max) ? 1 : 0
          areas[y][x] = FUNCTION
        end
      end
    end
    (8..size - 9).each do |i|
      symbol[i][6] = symbol[6][i] = i.even? ? 1 : 0
      areas[i][6] = areas[6][i] = FUNCTION
    end
    unless alignments.empty?
      first, last = alignments.first, alignments.last
      excluded = [[first, first], [first, last], [last, first]]
      alignments.each do |cy|
        alignments.each do |cx|
          next if excluded.include?([cx, cy])
          (-2..2).each do |dy|
            (-2..2).each do |dx|
              symbol[cy + dy][cx + dx] = [dx.abs, dy.abs].max == 1 ? 0 : 1
              areas[cy + dy][cx + dx] = FUNCTION
            end
          end
        end
      end
    end
    symbol[size - 8][8] = 1
    areas[size - 8][8] = FUNCTION
    format_positions(size).each do |positions|
      positions.each { |x, y| areas[y][x] = FORMAT; symbol[y][x] = 0 }
    end
    if version >= 7
      version_positions(size).each do |positions|
        positions.each { |x, y| areas[y][x] = VERSION }
        write_value(symbol, positions, version_information(version))
      end
    end
    [symbol, areas]
  end

  def self.reading_order(areas)
    size = areas.length
    columns = (size - 1).step(8, -2).to_a + [5, 3, 1]
    positions = []
    columns.each_with_index do |right, pair|
      rows = pair.even? ? (size - 1).downto(0) : (0...size).each
      rows.each { |y| [right, right - 1].each { |x| positions << [x, y] if areas[y][x] == DATA } }
    end
    positions
  end
end
