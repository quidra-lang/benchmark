module Dataset
  module_function

  def read_csv(path)
    File.readlines(path, chomp: true, encoding: Encoding::US_ASCII).drop(1).map do |line|
      line.split(',').map!(&:to_i)
    end
  end

  def read(directory = 'input')
    points = read_csv(File.join(directory, 'points.csv'))
    rectangles = read_csv(File.join(directory, 'rects.csv'))
    rows = File.readlines(File.join(directory, 'params.txt'), encoding: Encoding::US_ASCII).map(&:split)
    parameters = {
      world: rows[0][1].to_i,
      bucket: rows[1][1].to_i,
      maximum: rows[2][1].to_i,
      minimum: rows[2][2].to_i,
      cell_size: rows[3][1].to_i
    }
    commands = File.readlines(File.join(directory, 'queries.txt'), encoding: Encoding::US_ASCII).map do |line|
      name, *values = line.split
      [name, values.map!(&:to_i)]
    end
    [points, rectangles, parameters, commands]
  end
end
