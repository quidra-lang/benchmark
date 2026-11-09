require 'fileutils'

module Report
  LEVELS = ' .:-=+*#%@'.freeze
  module_function

  def decimal(number, places = 4)
    value = format("%.#{places}f", number)
    value.sub(/\A-0\.(0+)\z/, '0.\1')
  end

  def values(numbers) = numbers.map { |n| decimal(n) }.join(' ')
  def optional(number) = number.nil? ? '-' : decimal(number)

  def framed(rows)
    border = '+' + '-' * rows.first.length + '+'
    [border] + rows.map { |row| '|' + row.join + '|' } + [border]
  end

  def write_lines(name, lines)
    FileUtils.mkdir_p('output')
    File.write("output/#{name}", lines.join("\n") + "\n")
  end

  def write_blocks(name, blocks)
    write_lines(name, blocks.map { |block| block.join("\n") }.join("\n\n").split("\n", -1))
  end
end
