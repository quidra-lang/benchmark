module Density
  Point = Struct.new(:id, :x, :y, keyword_init: true)

  module Dataset
    module_function

    def read
      points = File.readlines('input/points.csv', chomp: true).drop(1).map do |line|
        id, x, y = line.split(',').map(&:to_i)
        Point.new(id: id, x: x, y: y)
      end.sort_by(&:id)
      parameters = {}
      File.readlines('input/params.txt', chomp: true).each do |line|
        key, *values = line.split
        parameters[key] = case key
                          when 'XI' then values.first.split('/').map(&:to_i)
                          when 'EPS', 'EXTRACT_EPS', 'MAP_SIZE', 'KDIST_PLOT'
                            values.map(&:to_i)
                          else
                            values.first.to_i
                          end
      end
      [points, parameters]
    end
  end
end
