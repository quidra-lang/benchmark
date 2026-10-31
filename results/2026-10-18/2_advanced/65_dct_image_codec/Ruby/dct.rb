module DCT
  ZIGZAG = (0...8).flat_map { |u| (0...8).map { |v| [u, v] } }.sort_by do |u, v|
    [u + v, (u + v).odd? ? u : -u]
  end.freeze
  module_function

  def rounded_shift(value, shift)
    (value + (1 << (shift - 1))) >> shift
  end

  def forward(block, transform)
    intermediate = Array.new(8) do |u|
      Array.new(8) do |x|
        total = 0
        8.times { |y| total += transform[u][y] * (block[y][x] - 128) }
        rounded_shift(total, 11)
      end
    end
    Array.new(8) do |u|
      Array.new(8) do |v|
        total = 0
        8.times { |x| total += intermediate[u][x] * transform[v][x] }
        rounded_shift(total, 15)
      end
    end
  end

  def inverse(coefficients, transform)
    intermediate = Array.new(8) do |y|
      Array.new(8) do |v|
        total = 0
        8.times { |u| total += transform[u][y] * coefficients[u][v] }
        rounded_shift(total, 11)
      end
    end
    Array.new(8) do |y|
      Array.new(8) do |x|
        total = 0
        8.times { |v| total += intermediate[y][v] * transform[v][x] }
        (rounded_shift(total, 15) + 128).clamp(0, 255)
      end
    end
  end

  def quantization_tables(basic, quality)
    scale = quality < 50 ? 5000 / quality : 200 - 2 * quality
    basic.each_with_index.to_h do |table, id|
      [id, table.map { |row| row.map { |v| ((v * scale + 50) / 100).clamp(1, 255) } }]
    end
  end

  def quantize(values, table)
    values.each_with_index.map do |row, u|
      row.each_with_index.map do |value, v|
        divisor = table[u][v]
        magnitude = (value.abs + divisor / 2) / divisor
        value.negative? ? -magnitude : magnitude
      end
    end
  end

  def zigzag(values)
    ZIGZAG.map { |u, v| values[u][v] }
  end

  def unzigzag(sequence)
    result = Array.new(8) { Array.new(8, 0) }
    ZIGZAG.each_with_index { |(u, v), i| result[u][v] = sequence[i] }
    result
  end

  def dequantize(sequence, table, keep = 64)
    result = Array.new(8) { Array.new(8, 0) }
    ZIGZAG.first(keep).each_with_index { |(u, v), i| result[u][v] = sequence[i] * table[u][v] }
    result
  end
end
