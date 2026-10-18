systems = [
  [[2, -1, 3, 7], [4, 1, -2, 3], [-3, 5, 1, -4]],
  [[1, 3, -2, 4, 6], [5, -2, 1, 3, -7], [-2, 4, 6, -1, 9], [3, 1, -4, 2, 5]]
]
systems.each_with_index do |system, number|
  a = system.map { |row| row.map(&:to_f) }
  n = a.length
  n.times do |k|
    pivot = (k...n).max_by { |row| a[row][k].abs }
    a[k], a[pivot] = a[pivot], a[k]
    (k + 1...n).each do |i|
      factor = a[i][k] / a[k][k]
      (k..n).each { |j| a[i][j] = a[i][j] - factor * a[k][j] }
    end
  end
  solution = Array.new(n, 0.0)
  (n - 1).downto(0) do |i|
    s = a[i][n]
    (i + 1...n).each { |j| s = s - a[i][j] * solution[j] }
    solution[i] = s / a[i][i]
  end
  puts "system #{number + 1}:"
  solution.each_with_index do |value, i|
    puts format('x%d = %.4f', i + 1, value.round(4, half: :up))
  end
end
