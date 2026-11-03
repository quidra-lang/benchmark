require 'fileutils'
require_relative 'evaluation'

module Plot
  extend self

  def real(value)
    result = format('%.4f', value)
    result == '-0.0000' ? '0.0000' : result
  end

  def reals(values)
    values.map { |value| real(value) }.join(' ')
  end

  def fraction_text(value)
    value ? "#{value.numerator}/#{value.denominator} #{real(value.to_f)}" : '-'
  end

  def ratio_text(numerator, denominator)
    fraction_text(Evaluation.reduced_fraction(numerator, denominator))
  end

  def frame(grid)
    border = '+' + '-' * grid.first.length + '+'
    [border, *grid.map { |row| '|' + row.join + '|' }, border]
  end

  def cell(value, low, high, size)
    ((value - low) / (high - low) * (size - 1) + 0.5).floor
  end

  def join_sections(sections)
    sections.each_with_object([]) do |section, lines|
      lines << '' unless lines.empty?
      lines.concat(section)
    end
  end

  def write_lines(path, lines)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, lines.join("\n") + "\n", encoding: 'US-ASCII')
  end
end
