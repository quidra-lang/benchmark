require 'fileutils'

module Report
  extend self

  def decimal(p, q)
    scaled = (2 * p * 10000 + q).div(2 * q)
    "#{scaled.div(10000)}.#{(scaled % 10000).to_s.rjust(4, '0')}"
  end

  def percentage(p, q)
    return '-' if q.zero?
    scaled = (2 * p * 10000 + q).div(2 * q)
    "#{scaled.div(100)}.#{(scaled % 100).to_s.rjust(2, '0')}"
  end

  def reduced_fraction(p, q)
    divisor = p.gcd(q)
    "#{p.div(divisor)}/#{q.div(divisor)}"
  end

  def hexadecimal(value) = value.to_s(16).rjust(8, '0')
  def register(value) = value.nil? ? '-' : "r#{value}"
  def cycle_heading(first, last) = 'cycle' + ' ' * 18 + (first..last).map { |cycle| cycle % 10 }.join

  def diagram_row(number, pc, kind, characters, annotation = '')
    identifier = number.nil? ? '     -' : number.to_s.rjust(6)
    "#{identifier} #{hexadecimal(pc)} #{kind.ljust(6)} #{characters}#{annotation}"
  end

  def join_parts(parts) = parts.flat_map.with_index { |part, i| i.zero? ? part : [''] + part }

  def write_lines(name, lines)
    FileUtils.mkdir_p('output')
    File.write(File.join('output', name), lines.join("\n") + "\n")
  end
end
