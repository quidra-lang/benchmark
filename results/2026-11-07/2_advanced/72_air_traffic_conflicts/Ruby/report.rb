require 'fileutils'

module Report
  module_function

  def decimal(value, digits = 3)
    rounded = value.round(digits, half: :up)
    rounded = 0.0 if rounded == 0
    format("%.#{digits}f", rounded)
  end

  def signed(value)
    value.positive? ? "+#{value}" : value.to_s
  end

  def named(**values)
    values.map { |key, value| "#{key}=#{value}" }.join(' ')
  end

  def chart(rows)
    border = '+' + '-' * rows.first.size + '+'
    [border, *rows.map { |row| "|#{row}|" }, border]
  end

  def write_lines(name, lines)
    FileUtils.mkdir_p('output')
    File.write(File.join('output', name), lines.empty? ? '' : lines.join("\n") + "\n", encoding: 'US-ASCII')
  end
end
