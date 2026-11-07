module Spectrum
  def real(value)
    text = format('%.4f', value)
    text == '-0.0000' ? '0.0000' : text
  end

  def fields(**items)
    items.map { |key, value| "#{key}=#{value.is_a?(Float) ? real(value) : value}" }.join(' ')
  end

  def write_lines(name, lines)
    Dir.mkdir('output') unless Dir.exist?('output')
    File.write(File.join('output', name), lines.join("\n") + "\n")
  end

  def write_csv(name, header, rows)
    write_lines(name, [header] + rows.map { |row| row.map { |v| v.is_a?(Float) ? real(v) : v.to_s }.join(',') })
  end

  def shade_lines(levels, fs, length)
    (length / 2).downto(0).map do |k|
      pixels = levels.map { |row| ' .:-=+*#%@'[row[k]] }.join
      "#{real(k * fs.to_f / length).rjust(9)} |#{pixels}|"
    end
  end
end
