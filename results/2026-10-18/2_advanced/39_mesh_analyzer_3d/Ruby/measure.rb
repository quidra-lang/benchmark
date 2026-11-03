module MeshAnalyzer
  module Measure
    extend self

    def subtract(a, b) = a.zip(b).map { |x, y| x - y }
    def dot(a, b) = a.zip(b).sum { |x, y| x * y }

    def cross(a, b)
      [a[1] * b[2] - a[2] * b[1],
       a[2] * b[0] - a[0] * b[2],
       a[0] * b[1] - a[1] * b[0]]
    end

    def normal(face, points)
      a, b, c = face.vertices.map { |vertex| points[vertex] }
      cross(subtract(b, a), subtract(c, a))
    end

    def determinant(face, points)
      a, b, c = face.vertices.map { |vertex| points[vertex] }
      dot(a, cross(b, c))
    end

    def area(faces, points)
      total = 0.0
      faces.each do |face|
        n = normal(face, points)
        total += Math.sqrt(dot(n, n))
      end
      total / 2
    end

    def triangle_angle(face, points)
      a, b, c = face.vertices.map { |vertex| points[vertex] }
      minimum = [dot(subtract(b, a), subtract(c, a)),
                 dot(subtract(c, b), subtract(a, b)),
                 dot(subtract(a, c), subtract(b, c))].min
      minimum.negative? ? 'obtuse' : (minimum.zero? ? 'right' : 'acute')
    end

    def edge_length_squared(edge, points)
      difference = subtract(points[edge[0]], points[edge[1]])
      dot(difference, difference)
    end

    def winding_number(ids, faces, points, sample)
      total = 0.0
      ids.each do |id|
        a, b, c = faces[id - 1].vertices.map { |vertex| subtract(points[vertex], sample) }
        la = Math.sqrt(dot(a, a))
        lb = Math.sqrt(dot(b, b))
        lc = Math.sqrt(dot(c, c))
        numerator = dot(a, cross(b, c))
        denominator = la * lb * lc + dot(a, b) * lc + dot(b, c) * la + dot(c, a) * lb
        total += 2 * Math.atan2(numerator, denominator)
      end
      (total / (4 * Math::PI)).round
    end

    def volume6(ids, faces, points)
      ids.sum { |id| determinant(faces[id - 1], points) }
    end

    def centroid(ids, faces, points, six_volume)
      3.times.map do |axis|
        numerator = ids.sum do |id|
          face = faces[id - 1]
          determinant(face, points) * face.vertices.sum { |vertex| points[vertex][axis] }
        end
        Rational(numerator, 4 * six_volume)
      end
    end

    def fraction(numerator, denominator = 1)
      value = Rational(numerator, denominator)
      value.denominator == 1 ? value.numerator.to_s : "#{value.numerator}/#{value.denominator}"
    end

    def real(value) = format('%.3f', value)

    def bbox(vertices, points)
      locations = vertices.map { |vertex| points[vertex] }
      3.times.map { |axis| locations.map { |point| point[axis] }.min } +
        3.times.map { |axis| locations.map { |point| point[axis] }.max }
    end
  end
end
