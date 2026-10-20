module PgmIO
  module_function

  def read_image(path)
    rows = File.readlines(path, chomp: true)
    width, height = rows[1].split.map(&:to_i)
    rows.drop(3).first(height).map { |row| row.split.map(&:to_i).first(width) }
  end

  def read_trig(path)
    File.readlines(path).map { |line| line.split.map(&:to_i).drop(1) }
  end

  def read_params(path)
    File.readlines(path).to_h do |line|
      name, *values = line.split
      numbers = values.map(&:to_i)
      [name.to_sym, name == 'gauss_kernel' ? numbers : numbers.first]
    end
  end

  def write_lines(name, lines)
    File.write("output/#{name}", lines.join("\n") + "\n")
  end

  def write_image(name, image)
    write_lines(name, ['P2', "#{image.first.length} #{image.length}", '255'] +
                      image.map { |row| row.join(' ') })
  end
end
