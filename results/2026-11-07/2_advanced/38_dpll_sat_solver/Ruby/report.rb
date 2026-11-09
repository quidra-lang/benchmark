require 'fileutils'

module SatReport
  module_function

  def named(**items)
    items.map { |key, value| "#{key}=#{value}" }.join(' ')
  end

  def number_list(values)
    values.empty? ? '-' : values.join(',')
  end

  def frequency(values)
    counts = values.tally
    counts.empty? ? '-' : counts.sort.map { |value, count| "#{value}:#{count}" }.join(',')
  end

  def board(columns)
    columns.map { |c| '.' * (c - 1) + 'Q' + '.' * (columns.length - c) }
  end

  def write_lines(filename, lines)
    FileUtils.mkdir_p('output')
    File.write(File.join('output', filename), lines.empty? ? '' : lines.join("\n") + "\n")
  end

  def write_paragraphs(filename, paragraphs)
    text = paragraphs.map { |lines| lines.join("\n") }.join("\n\n")
    write_lines(filename, text.empty? ? [] : [text])
  end
end
