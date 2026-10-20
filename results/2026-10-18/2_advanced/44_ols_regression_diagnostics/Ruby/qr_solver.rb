module QRSolver
  # Enumerable#sum compensates floating-point errors; this task requires plain additions.
  def total(values)
    result = 0.0
    values.each { |value| result += block_given? ? yield(value) : value }
    result
  end
  module_function :total

  class Fit
    include QRSolver
    attr_reader :matrix, :response, :weights, :n, :p, :rank, :accepted, :aliases,
                :triangular, :effects, :beta, :inverse, :variance, :u, :g,
                :leverage, :fitted, :residual, :weighted_residual, :rss

    def initialize(matrix, response, weights, tolerance)
      @matrix, @response, @weights = matrix, response, weights
      @n, @p = matrix.length, matrix[0].length
      roots = weights.map { |weight| Math.sqrt(weight) }
      weighted = matrix.each_with_index.map { |row, i| row.map { |value| roots[i] * value } }
      lengths = Array.new(@p) { |j| Math.sqrt(total(0...@n) { |i| weighted[i][j] * weighted[i][j] }) }
      work = weighted.map(&:dup)
      transformed = Array.new(@n) { |i| roots[i] * response[i] }
      triangular = Array.new(@p) { Array.new(@p, 0.0) }
      @accepted, @aliases = [], []
      @p.times do |j|
        k = @accepted.length
        eta = Math.sqrt(total(k...@n) { |i| work[i][j] * work[i][j] })
        if lengths[j].zero? || eta <= tolerance * lengths[j]
          @aliases << j
          next
        end
        @accepted << j
        alpha = work[k][j] >= 0.0 ? -eta : eta
        vector = [work[k][j] - alpha] + ((k + 1)...@n).map { |i| work[i][j] }
        squared_length = total(vector) { |value| value * value }
        k.times { |l| triangular[l][k] = work[l][j] }
        triangular[k][k] = alpha
        ((j + 1)...@p).each do |l|
          dot = total(k...@n) { |i| vector[i - k] * work[i][l] }
          delta = 2.0 * dot / squared_length
          (k...@n).each { |i| work[i][l] -= delta * vector[i - k] }
        end
        dot = total(k...@n) { |i| vector[i - k] * transformed[i] }
        delta = 2.0 * dot / squared_length
        (k...@n).each { |i| transformed[i] -= delta * vector[i - k] }
      end

      @rank = @accepted.length
      r = @rank
      @triangular = triangular.first(r).map { |row| row.first(r) }
      @effects = transformed.first(r)
      @beta = Array.new(@p)
      (r - 1).downto(0) do |k|
        tail = total((k + 1)...r) { |l| @triangular[k][l] * @beta[@accepted[l]] }
        @beta[@accepted[k]] = (@effects[k] - tail) / @triangular[k][k]
      end
      @inverse = Array.new(r) { Array.new(r, 0.0) }
      r.times do |m|
        (r - 1).downto(0) do |l|
          diagonal = l == m ? 1.0 : 0.0
          tail = total((l + 1)...r) { |q| @triangular[l][q] * @inverse[q][m] }
          @inverse[l][m] = (diagonal - tail) / @triangular[l][l]
        end
      end
      @variance = @inverse.map { |row| total(row) { |value| value * value } }
      @u, @g, @leverage, @fitted, @residual, @weighted_residual = [], [], [], [], [], []
      @n.times do |i|
        u = Array.new(r) do |k|
          total(0...r) { |m| weighted[i][@accepted[m]] * @inverse[m][k] }
        end
        @u << u
        @leverage << total(u) { |value| value * value }
        @g << Array.new(r) { |k| total(0...r) { |m| @inverse[k][m] * u[m] } }
        value = total(0...r) { |k| matrix[i][@accepted[k]] * @beta[@accepted[k]] }
        @fitted << value
        @residual << response[i] - value
        @weighted_residual << roots[i] * @residual[i]
      end
      @rss = total(@weighted_residual) { |value| value * value }
    end
  end
end
