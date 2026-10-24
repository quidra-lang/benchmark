module Render
  def self.symbol_lines(symbol)
    symbol.map { |row| row.map { |value| value == 1 ? '#' : '.' }.join }
  end

  def self.pbm_text(symbol, quiet_zone, scale)
    width = (symbol.length + 2 * quiet_zone) * scale
    margin = '0' * (quiet_zone * scale)
    empty = '0' * width
    lines = ['P1', "#{width} #{width}"]
    lines.concat(Array.new(quiet_zone * scale, empty))
    symbol.each do |row|
      pixels = margin + row.map { |value| value.to_s * scale }.join + margin
      lines.concat(Array.new(scale, pixels))
    end
    lines.concat(Array.new(quiet_zone * scale, empty))
    lines.join("\n") + "\n"
  end
end
