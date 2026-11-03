module MeshAnalyzer
  Face = Struct.new(:vertices, :triangle, :polygon, :line, :group, keyword_init: true)

  module Repair
    extend self

    def split_polygons(polygons)
      triangles = []
      polygons.each do |polygon|
        corners = polygon.vertices
        (1...corners.length - 1).each do |index|
          triangles << Face.new(vertices: [corners[0], corners[index], corners[index + 1]],
                                triangle: triangles.length + 1, polygon: polygon.number,
                                line: polygon.line, group: polygon.group)
        end
      end
      triangles
    end

    def snap(vertices, spacing)
      points, changed = [nil], []
      vertices.drop(1).each_with_index do |point, index|
        rounded = point.map { |coordinate| spacing * (2 * coordinate + spacing).div(2 * spacing) }
        points << rounded
        changed << [index + 1, point, rounded] if rounded != point
      end
      [points, changed]
    end

    def representatives(points, merge)
      owners = {}
      chosen = points.drop(1).each_with_index.map do |point, index|
        merge ? (owners[point] ||= index + 1) : index + 1
      end
      [0] + chosen
    end

    def clean(triangles, points, representatives, remove_zero, remove_duplicate)
      faces, removed = [], []
      seen = Set.new
      triangles.each do |triangle|
        corners = triangle.vertices.map { |vertex| representatives[vertex] }
        face = triangle.dup
        face.vertices = corners
        reason = if corners.uniq.length < 3
                   'repeated'
                 elsif remove_zero && Measure.normal(face, points) == [0, 0, 0]
                   'zero_area'
                 elsif remove_duplicate && seen.include?(corners.sort)
                   'duplicate'
                 end
        if reason
          removed << [triangle, reason]
        else
          seen.add(corners.sort)
          faces << face
        end
      end
      [faces, removed]
    end

    def fill_triangles(corners)
      (2...corners.length).map do |index|
        Face.new(vertices: [corners[0], corners[index], corners[index - 1]], group: 'fill')
      end
    end
  end
end
