module KMeans
  module_function

  def distance2(a, b)
    dx, dy = a[0] - b[0], a[1] - b[1]
    dx * dx + dy * dy
  end

  def distance(a, b) = Math.sqrt(distance2(a, b))

  def assign(points, centers)
    points.map { |p| centers.each_index.min_by { |k| [distance2(p, centers[k]), k] } }
  end

  def fit(points, initial, maximum)
    centers = initial.map(&:dup)
    assignment = assign(points, centers)
    iterations = 0
    maximum.times do |t|
      centers = centers.each_with_index.map do |old, k|
        sx = sy = 0.0
        count = 0
        points.each_with_index do |(x, y), i|
          next unless assignment[i] == k
          sx += x
          sy += y
          count += 1
        end
        count.zero? ? old : [sx / count, sy / count]
      end
      updated = assign(points, centers)
      iterations = t + 1
      stopped = updated == assignment
      assignment = updated
      break if stopped
    end
    inertia = 0.0
    points.each_with_index { |p, i| inertia += distance2(p, centers[assignment[i]]) }
    {centers: centers, assignment: assignment, iterations: iterations, inertia: inertia,
     sizes: centers.each_index.map { |k| assignment.count(k) }}
  end
end
