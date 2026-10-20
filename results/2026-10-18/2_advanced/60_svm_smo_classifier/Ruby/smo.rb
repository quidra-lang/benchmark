class Model
  attr_reader :points, :labels, :kernel, :matrix, :c, :alpha, :b, :full_passes,
              :nonbound_passes, :examined, :steps, :choices, :clipping, :records, :converged

  def initialize(points, labels, kernel, matrix, c, settings)
    @points, @labels, @kernel, @matrix, @c = points, labels, kernel, matrix, c
    @tolerance, @eps, @max_passes = settings.tolerance, settings.eps, settings.max_passes
    @alpha, @errors, @b = Array.new(points.size, 0.0), labels.map { |y| -y.to_f }, 0.0
    @full_passes = @nonbound_passes = @examined = @steps = 0
    @choices = { heuristic: 0, nonbound_loop: 0, full_loop: 0 }
    @clipping = { none: 0, lower: 0, upper: 0 }
    @records, @converged = [], false
  end

  def passes = @full_passes + @nonbound_passes
  def nonbound?(i) = @alpha[i] > 0 && @alpha[i] < @c
  def snap(a) = a < 0.00000001 ? 0.0 : (a > @c - 0.00000001 ? @c : a)

  def take(i1, i2)
    return false if i1 == i2
    alpha1, alpha2, y1, y2, e1, e2 = @alpha[i1], @alpha[i2], @labels[i1], @labels[i2], @errors[i1], @errors[i2]
    if y1 != y2
      lo, hi = [0.0, alpha2 - alpha1].max, [@c, @c + alpha2 - alpha1].min
    else
      lo, hi = [0.0, alpha2 + alpha1 - @c].max, [@c, alpha2 + alpha1].min
    end
    return false if lo == hi
    k11, k12, k22 = @matrix[i1][i1], @matrix[i1][i2], @matrix[i2][i2]
    eta = k11 + k22 - 2 * k12
    return false if eta <= 0
    a2 = alpha2 + y2 * (e1 - e2) / eta
    clip = :none
    if a2 < lo
      a2, clip = lo, :lower
    elsif a2 > hi
      a2, clip = hi, :upper
    end
    a2 = snap(a2)
    return false if (a2 - alpha2).abs < @eps * (a2 + alpha2 + @eps)
    a1 = snap(alpha1 + y1 * y2 * (alpha2 - a2))
    t1, t2 = y1 * (a1 - alpha1), y2 * (a2 - alpha2)
    b1 = e1 + t1 * k11 + t2 * k12 + @b
    b2 = e2 + t1 * k12 + t2 * k22 + @b
    threshold = if a1 > 0 && a1 < @c then b1
                elsif a2 > 0 && a2 < @c then b2
                else (b1 + b2) / 2.0 end
    delta = threshold - @b
    @points.each_index { |i| @errors[i] = @errors[i] + (t1 * @matrix[i1][i] + t2 * @matrix[i2][i] - delta) }
    @errors[i1] = 0.0 if a1 > 0 && a1 < @c
    @errors[i2] = 0.0 if a2 > 0 && a2 < @c
    @alpha[i1], @alpha[i2], @b = a1, a2, threshold
    @steps += 1
    @clipping[clip] += 1
    true
  end

  def examine(i2)
    @examined += 1
    r = @errors[i2] * @labels[i2]
    return 0 unless (r < -@tolerance && @alpha[i2] < @c) || (r > @tolerance && @alpha[i2] > 0)
    partner, largest = nil, -1.0
    @points.each_index do |i|
      next unless i != i2 && nonbound?(i)
      difference = (@errors[i] - @errors[i2]).abs
      partner, largest = i, difference if difference > largest
    end
    if partner && take(partner, i2)
      @choices[:heuristic] += 1
      return 1
    end
    @points.each_index do |i|
      if nonbound?(i) && take(i, i2)
        @choices[:nonbound_loop] += 1
        return 1
      end
    end
    @points.each_index do |i|
      if take(i, i2)
        @choices[:full_loop] += 1
        return 1
      end
    end
    0
  end

  def fit
    all = true
    loop do
      before, changed = @examined, 0
      @points.each_index { |i| changed += examine(i) if all || nonbound?(i) }
      all ? @full_passes += 1 : @nonbound_passes += 1
      record = { full: all, examined: @examined - before, changed: changed }
      record[:alpha] = @alpha.dup if all
      @records << record
      if all && changed.zero?
        @converged = true
        break
      end
      break if passes == @max_passes
      all = all ? false : (changed.zero? ? true : false)
    end
    self
  end

  def decision(point)
    total = 0.0
    @alpha.each_with_index { |a, i| total += a * @labels[i] * @kernel.value(@points[i], point) if a > 0 }
    total - @b
  end

  def training_decisions
    @matrix.map do |row|
      total = 0.0
      @alpha.each_with_index { |a, i| total += a * @labels[i] * row[i] if a > 0 }
      total - @b
    end
  end
end

def train(points, labels, kernel, matrix, c, settings) = Model.new(points, labels, kernel, matrix, c, settings).fit
