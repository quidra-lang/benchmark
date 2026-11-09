require 'fileutils'

module Report
  module_function

  def fraction(numerator, denominator)
    divisor = numerator.gcd(denominator)
    "#{numerator / divisor}/#{denominator / divisor}"
  end

  def ids(values)
    values.empty? ? '-' : values.join(' ')
  end

  def distances(values)
    ids(values.map { |id, distance| "#{id}:#{distance}" })
  end

  def write_lines(path, lines)
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, 'wb') do |file|
      lines.each { |line| file.write(line, "\n") }
    end
  end
end
