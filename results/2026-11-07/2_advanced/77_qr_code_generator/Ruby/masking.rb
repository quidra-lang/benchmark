module Masking
  def self.condition(mask, x, y)
    case mask
    when 0 then (y + x) % 2 == 0
    when 1 then y % 2 == 0
    when 2 then x % 3 == 0
    when 3 then (y + x) % 3 == 0
    when 4 then (y / 2 + x / 3) % 2 == 0
    when 5 then (y * x) % 2 + (y * x) % 3 == 0
    when 6 then ((y * x) % 2 + (y * x) % 3) % 2 == 0
    when 7 then ((y + x) % 2 + (y * x) % 3) % 2 == 0
    end
  end

  def self.apply(symbol, positions, mask)
    result = symbol.map(&:dup)
    positions.each { |x, y| result[y][x] ^= 1 if condition(mask, x, y) }
    result
  end

  def self.penalties(symbol)
    size = symbol.length
    n1, n2, n3 = 0, 0, 0
    patterns = ['10111010000', '00001011101']
    (symbol + symbol.transpose).each do |line|
      line.chunk(&:itself).each { |_, run| n1 += run.length - 2 if run.length >= 5 }
      text = line.join
      (0...size - 10).each { |start| n3 += 40 if patterns.include?(text[start, 11]) }
    end
    (size - 1).times do |y|
      (size - 1).times do |x|
        value = symbol[y][x]
        n2 += 3 if [symbol[y][x + 1], symbol[y + 1][x], symbol[y + 1][x + 1]].all? { |v| v == value }
      end
    end
    dark = symbol.sum(&:sum)
    n4 = 10 * ((20 * dark - 10 * size * size).abs / (size * size))
    [n1, n2, n3, n4]
  end
end
