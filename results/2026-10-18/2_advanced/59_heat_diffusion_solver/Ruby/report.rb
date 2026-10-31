require 'fileutils'

module Report
  def self.real(value, places)
    text = format("%.#{places}f", value)
    text == '-0.' + '0' * places ? text.delete_prefix('-') : text
  end

  def self.time(milliseconds) = format('%d.%03d', milliseconds / 1000, milliseconds % 1000)

  def self.field_lines(mesh, field)
    field.each_slice(mesh.width).map { |row| row.map { |value| real(value, 2) }.join(' ') }
  end

  def self.isotherms(mesh, field, bands)
    hottest = field.each_index.max_by { |p| [field[p], -p] }
    counts = Array.new(bands.size + 1, 0)
    characters = field.each_with_index.map do |value, p|
      digit = bands.count { |boundary| boundary <= value }
      counts[digit] += 1
      p == hottest ? '*' : digit.to_s
    end
    [counts, characters.each_slice(mesh.width).map(&:join)]
  end

  def self.write(name, lines)
    FileUtils.mkdir_p('output')
    File.write(File.join('output', name), lines.join("\n") + "\n", encoding: Encoding::US_ASCII)
  end
end
