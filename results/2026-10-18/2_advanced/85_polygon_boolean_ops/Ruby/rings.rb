require_relative 'intersections'

module Rings
  module_function

  def edges(ring)
    ring.each_with_index.map { |point, index| [point, ring[(index + 1) % ring.size]] }
  end

  def inside?(ring, point)
    parity = false
    edges(ring).each do |first, second|
      next if (first[1] > point[1]) == (second[1] > point[1])
      low, high = first[1] < second[1] ? [first, second] : [second, first]
      parity = !parity if RationalGeometry.cross(low, high, point).positive?
    end
    parity
  end

  def interior?(sequence, point)
    parity = false
    sequence.each { |ring| parity = !parity if inside?(ring, point) }
    parity
  end

  def boundary?(ring, point)
    edges(ring).any? { |first, second| Intersections.on_segment?(point, first, second) }
  end

  def rotate(ring)
    index = ring.each_index.min_by { |position| RationalGeometry.point_key(ring[position]) }
    ring.rotate(index)
  end

  def counterclockwise?(ring)
    RationalGeometry.cross(ring[-1], ring[0], ring[1]).positive?
  end

  def reverse(ring)
    [ring.first] + ring.drop(1).reverse
  end

  def normalize(ring, outer)
    result = rotate(ring)
    counterclockwise?(result) == outer ? result : reverse(result)
  end

  def assemble(result_rings)
    rotated = result_rings.map { |ring| rotate(ring) }
    depths = rotated.each_with_index.map do |ring, index|
      rotated.each_with_index.count { |other, other_index| other_index != index && inside?(other, ring.first) }
    end
    oriented = rotated.each_with_index.map do |ring, index|
      counterclockwise?(ring) == depths[index].even? ? ring : reverse(ring)
    end
    outers = depths.each_index.select { |index| depths[index].even? }
    outers.sort_by! { |index| RationalGeometry.point_key(oriented[index].first) }
    outers.map do |index|
      outer = oriented[index]
      holes = oriented.each_with_index.filter_map do |ring, hole_index|
        ring if depths[hole_index] == depths[index] + 1 && inside?(outer, ring.first)
      end
      [outer, *holes.sort_by { |ring| RationalGeometry.point_key(ring.first) }]
    end
  end

  def area(ring)
    total = 0.0
    edges(ring).each do |first, second|
      x1, y1 = first.map { |value| RationalGeometry.real(value) }
      x2, y2 = second.map { |value| RationalGeometry.real(value) }
      total += x1 * y2 - x2 * y1
    end
    total / 2.0
  end

  def perimeter(ring)
    total = 0.0
    edges(ring).each do |first, second|
      x1, y1 = first.map { |value| RationalGeometry.real(value) }
      x2, y2 = second.map { |value| RationalGeometry.real(value) }
      dx, dy = x2 - x1, y2 - y1
      total += Math.sqrt(dx * dx + dy * dy)
    end
    total
  end
end
