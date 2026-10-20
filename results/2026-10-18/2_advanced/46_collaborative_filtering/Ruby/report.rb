require 'fileutils'

module Report
  module_function

  def real(value)
    return '-' if value.nil?

    text = format('%.4f', value)
    text == '-0.0000' ? '0.0000' : text
  end

  def optional(value)
    value.nil? ? '-' : value.to_s
  end

  def write_lines(path, lines)
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, 'w:US-ASCII') do |file|
      lines.each { |line| file.write(line, "\n") }
    end
  end
end
