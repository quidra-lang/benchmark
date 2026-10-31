require 'fileutils'

module Report
  module_function

  def real(value, digits)
    return 'none' if value.nil?
    text = format("%.#{digits}f", value)
    text.to_f.zero? ? format("%.#{digits}f", 0.0) : text
  end

  def plot_lines(cells, heights)
    labels = heights.map { |height| real(height / 100.0, 2) }
    width = labels.map(&:length).max
    lines = cells.each_with_index.map { |row, index| labels[index].rjust(width) + ' |' + row.join + '|' }
    lines << ' ' * width + ' +' + Array.new(cells[0].length) { |c| (c % 6).zero? ? '+' : '-' }.join + '+'
    lines
  end

  def write_files(files)
    FileUtils.mkdir_p('output')
    files.each { |name, lines| File.write("output/#{name}", lines.join("\n") + "\n", encoding: Encoding::US_ASCII) }
  end
end
