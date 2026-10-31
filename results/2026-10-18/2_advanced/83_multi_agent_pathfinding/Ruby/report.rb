require 'fileutils'

module Report
  DIRECTIONS = { [0, 0] => '.', [0, -1] => 'N', [1, 0] => 'E', [0, 1] => 'S', [-1, 0] => 'W' }.freeze
  def self.cell(cell) = cell.join(',')
  def self.agent(id) = (65 + id).chr
  def self.csv(values) = values.join(',')

  def self.actions(path)
    path.each_cons(2).map { |u, v| DIRECTIONS.fetch([v[0] - u[0], v[1] - u[1]]) }.join
  end

  def self.conflict(conflict)
    c = conflict
    prefix = "#{c.kind} t #{c.time} #{agent(c.a)} #{agent(c.b)}"
    c.kind == 'vertex' ? "#{prefix} at #{cell(c.u)}" : "#{prefix} from #{cell(c.u)} to #{cell(c.v)}"
  end

  def self.fraction(numerator, denominator)
    divisor = numerator.gcd(denominator)
    "#{numerator / divisor}/#{denominator / divisor}"
  end

  def self.write(name, lines)
    FileUtils.mkdir_p('output')
    File.write(File.join('output', name), lines.join("\n") + "\n", encoding: 'ASCII')
  end
end
