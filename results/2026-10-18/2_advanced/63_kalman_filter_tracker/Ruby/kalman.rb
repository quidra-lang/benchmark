require_relative 'matrix'

class Kalman
  attr_accessor :x, :p
  attr_reader :xp, :pp, :f

  def self.transition(model, t)
    result = Mat.identity(model == 'CV' ? 4 : 6)
    result[0][2] = result[1][3] = t
    if model == 'CA'
      result[0][4] = result[1][5] = t * t / 2.0
      result[2][4] = result[3][5] = t
    end
    result
  end

  def self.process_noise(model, t, q)
    if model == 'CV'
      result = Mat.zeros(4)
      entries = [[0, 0, q * t * t * t / 3.0], [0, 2, q * t * t / 2.0], [2, 2, q * t]]
    else
      result = Mat.zeros(6)
      entries = [[0, 0, q * t * t * t * t * t / 20.0], [0, 2, q * t * t * t * t / 8.0],
                 [0, 4, q * t * t * t / 6.0], [2, 2, q * t * t * t / 3.0],
                 [2, 4, q * t * t / 2.0], [4, 4, q * t]]
    end
    2.times do |axis|
      entries.each do |row, column, value|
        result[row + axis][column + axis] = value
        result[column + axis][row + axis] = value
      end
    end
    result
  end

  def initialize(model, q, sigma, velocity_variance, acceleration_variance, measurement)
    @model, @q = model, q
    size = model == 'CV' ? 4 : 6
    @x = measurement + Array.new(size - 2, 0.0)
    variances = [sigma * sigma, sigma * sigma, velocity_variance, velocity_variance]
    variances += [acceleration_variance, acceleration_variance] if size == 6
    @p = Mat.diagonal(variances)
    @h = Mat.zeros(2, size)
    @h[0][0] = @h[1][1] = 1.0
    @r = Mat.diagonal([sigma * sigma, sigma * sigma])
    @f = @xp = @pp = nil
  end

  def predict(interval)
    @f = self.class.transition(@model, interval)
    @x = Mat.matrix_vector(@f, @x)
    @p = Mat.add(Mat.product(Mat.product(@f, @p), Mat.transpose(@f)), self.class.process_noise(@model, interval, @q))
    @xp, @pp = @x, @p
  end

  def innovation(measurement)
    residual = Mat.vector_subtract(measurement, Mat.matrix_vector(@h, @x))
    covariance = Mat.add(Mat.product(Mat.product(@h, @p), Mat.transpose(@h)), @r)
    precision = Mat.inverse(covariance)
    [residual, covariance, precision, Mat.quadratic2(residual, precision)]
  end

  def update(measurement, innovation = nil)
    residual, covariance, precision, distance2 = innovation || self.innovation(measurement)
    gain = Mat.product(Mat.product(@p, Mat.transpose(@h)), precision)
    correction = Mat.subtract(Mat.identity(@x.length), Mat.product(gain, @h))
    @x = Mat.vector_add(@x, Mat.matrix_vector(gain, residual))
    @p = Mat.add(Mat.product(Mat.product(correction, @p), Mat.transpose(correction)),
                 Mat.product(Mat.product(gain, @r), Mat.transpose(gain)))
    likelihood = -Math.log(2 * Math::PI) - Math.log(Mat.determinant2(covariance)) / 2.0 - distance2 / 2.0
    [distance2, likelihood, covariance]
  end

  def snapshot
    { x: @x, p: @p, xp: @xp, pp: @pp, f: @f }
  end

  def self.smooth(history)
    states = Array.new(history.length)
    states[-1] = history[-1][:x]
    (history.length - 2).downto(0) do |i|
      current, following = history[i], history[i + 1]
      gain = Mat.product(Mat.product(current[:p], Mat.transpose(following[:f])), Mat.inverse(following[:pp]))
      difference = Mat.vector_subtract(states[i + 1], following[:xp])
      states[i] = Mat.vector_add(current[:x], Mat.matrix_vector(gain, difference))
    end
    states
  end
end
