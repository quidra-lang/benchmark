points = [
  [3, 2], [-6, 1], [8, 4], [0, 0], [-3, 7], [4, -3], [1, -5], [-2, 1],
  [5, 6], [-6, -2], [2, -2], [7, -1], [-3, 4], [2, 8], [-6, 3]
]

def cross(o, a, b)
  (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
end

def chain(ordered)
  result = []
  ordered.each do |point|
    result.pop while result.length >= 2 && cross(result[-2], result[-1], point) <= 0
    result << point
  end
  result
end

ordered = points.sort
hull = chain(ordered)[0...-1] + chain(ordered.reverse)[0...-1]
area_twice = (hull + [hull.first]).each_cons(2).sum do |(x, y), (next_x, next_y)|
  x * next_y - next_x * y
end
puts "hull: #{hull.length} points"
hull.each { |x, y| puts "(#{x}, #{y})" }
puts format('area: %.1f', area_twice / 2.0)
