module Locator
  PI = 3.141592653589793
  module_function

  def distance(solution, station)
    dx = solution[0].to_f - station[:x].to_f
    dy = solution[1].to_f - station[:y].to_f
    dz = solution[2].to_f + station[:elevation].to_f
    Math.sqrt(dx * dx + dy * dy + dz * dz)
  end

  def residuals(solution, observations, velocity)
    observations.map { |station, time| time - solution[3] - distance(solution, station) / velocity.to_f }
  end

  def rms(solution, observations, velocity)
    total = 0.0
    residuals(solution, observations, velocity).each { |r| total += r * r }
    Math.sqrt(total / observations.length.to_f)
  end

  def grid_search(observations, params)
    ranges = %i[grid_x grid_y grid_z].map do |key|
      low, high, step = params[key]
      low.step(high, step).to_a
    end
    best = nil
    minimum = Float::INFINITY
    profile = {}
    ranges[0].each do |x|
      ranges[1].each do |y|
        ranges[2].each do |z|
          solution = [x.to_f, y.to_f, z.to_f, 0.0]
          deltas = observations.map { |station, time| time - distance(solution, station) / params[:velocity].to_f }
          total = 0.0
          deltas.each { |delta| total += delta }
          origin = total / deltas.length.to_f
          error = 0.0
          deltas.each { |delta| error += (delta - origin) * (delta - origin) }
          if error < minimum
            best = [x.to_f, y.to_f, z.to_f, origin]
            minimum = error
          end
          profile[z] = error if !profile.key?(z) || error < profile[z]
        end
      end
    end
    {solution: best, rms: Math.sqrt(minimum / observations.length.to_f),
     profile: ranges[2].map { |z| Math.sqrt(profile[z] / observations.length.to_f) }}
  end

  def cholesky(matrix)
    lower = Array.new(4) { Array.new(4, 0.0) }
    4.times do |row|
      (0..row).each do |col|
        total = 0.0
        col.times { |i| total += lower[row][i] * lower[col][i] }
        value = matrix[row][col] - total
        lower[row][col] = row == col ? Math.sqrt(value) : value / lower[col][col]
      end
    end
    lower
  end

  def solve(lower, right)
    forward = Array.new(4, 0.0)
    4.times do |row|
      total = 0.0
      row.times { |col| total += lower[row][col] * forward[col] }
      forward[row] = (right[row] - total) / lower[row][row]
    end
    result = Array.new(4, 0.0)
    3.downto(0) do |row|
      total = 0.0
      (row + 1...4).each { |col| total += lower[col][row] * result[col] }
      result[row] = (forward[row] - total) / lower[row][row]
    end
    result
  end

  def normals(solution, observations, velocity)
    matrix = Array.new(4) { Array.new(4, 0.0) }
    right = Array.new(4, 0.0)
    errors = residuals(solution, observations, velocity)
    observations.each_with_index do |(station, _), index|
      d = distance(solution, station)
      denominator = velocity.to_f * d
      gradient = [(solution[0] - station[:x].to_f) / denominator,
                  (solution[1] - station[:y].to_f) / denominator,
                  (solution[2] + station[:elevation].to_f) / denominator, 1.0]
      4.times do |row|
        right[row] += gradient[row] * errors[index]
        4.times { |col| matrix[row][col] += gradient[row] * gradient[col] }
      end
    end
    [matrix, right]
  end

  def geiger(initial, observations, velocity)
    solution = initial.map(&:to_f)
    trace = []
    8.times do |iteration|
      matrix, right = normals(solution, observations, velocity)
      delta = solve(cholesky(matrix), right)
      4.times { |axis| solution[axis] += delta[axis] }
      solution[2] = 0.0 if solution[2] < 0.0
      trace << {number: iteration + 1, solution: solution.dup, rms: rms(solution, observations, velocity)}
    end
    {solution: solution, trace: trace, residuals: residuals(solution, observations, velocity),
     rms: rms(solution, observations, velocity)}
  end

  def run(observations, params)
    grid = grid_search(observations, params)
    geiger(grid[:solution], observations, params[:velocity]).merge(grid: grid)
  end

  def error_ellipse(solution, observations, velocity)
    matrix, = normals(solution, observations, velocity)
    lower = cholesky(matrix)
    columns = 4.times.map { |col| solve(lower, 4.times.map { |row| row == col ? 1.0 : 0.0 }) }
    squares = 0.0
    residuals(solution, observations, velocity).each { |r| squares += r * r }
    variance = squares / (observations.length - 4).to_f
    covariance = 4.times.map { |row| 4.times.map { |col| variance * columns[col][row] } }
    xx, yy, xy = covariance[0][0], covariance[1][1], covariance[0][1]
    mu = (xx + yy) / 2.0
    half_difference = (xx - yy) / 2.0
    rho = Math.sqrt(half_difference * half_difference + xy * xy)
    theta = Math.atan2(2.0 * xy, xx - yy) / 2.0 * 180.0 / PI
    {covariance: covariance, smaj: Math.sqrt(mu + rho), smin: Math.sqrt(mu - rho),
     az: (90.0 - theta) % 180.0, erz: Math.sqrt(covariance[2][2]), ert: Math.sqrt(covariance[3][3])}
  end
end
