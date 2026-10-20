module Density
  class GridIndex
    attr_reader :cells, :neighbours, :candidates, :brute_counts, :busiest

    def self.distance(first, second)
      dx = first.x - second.x
      dy = first.y - second.y
      dx * dx + dy * dy
    end

    def initialize(points, radius)
      @cells = Hash.new { |hash, cell| hash[cell] = [] }
      points.each_with_index do |point, index|
        @cells[[point.x / radius, point.y / radius]] << index
      end
      @neighbours = Array.new(points.length) { [] }
      @candidates = Array.new(points.length, 0)
      squared_radius = radius * radius
      points.each_with_index do |point, index|
        gx = point.x / radius
        gy = point.y / radius
        (gy - 1..gy + 1).each do |row|
          (gx - 1..gx + 1).each do |column|
            @cells.fetch([column, row], []).each do |other|
              @candidates[index] += 1
              if self.class.distance(point, points[other]) <= squared_radius
                @neighbours[index] << other
              end
            end
          end
        end
      end
      @brute_counts = points.map do |point|
        points.count { |other| self.class.distance(point, other) <= squared_radius }
      end
      gx, gy = @cells.keys.min_by { |x, y| [-@cells[[x, y]].length, y, x] }
      @busiest = [gx, gy, @cells[[gx, gy]].length]
    end
  end
end
