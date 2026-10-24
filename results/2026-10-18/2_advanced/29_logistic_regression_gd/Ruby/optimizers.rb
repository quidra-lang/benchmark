require_relative 'logistic'

module Optimizers
  class Minstd
    def initialize(seed)
      @state = seed
    end

    def draw
      @state = 48_271 * @state % 2_147_483_647
    end

    def shuffle!(sequence)
      (sequence.length - 1).downto(1) do |index|
        other = draw % (index + 1)
        sequence[index], sequence[other] = sequence[other], sequence[index]
      end
      sequence
    end
  end

  def self.cholesky(matrix)
    size = matrix.length
    lower = Array.new(size) { Array.new(size, 0.0) }
    size.times do |column|
      (column...size).each do |row|
        total = 0.0
        column.times { |index| total += lower[row][index] * lower[column][index] }
        remainder = matrix[row][column] - total
        lower[row][column] = row == column ? Math.sqrt(remainder) : remainder / lower[column][column]
      end
    end
    lower
  end

  def self.solve(lower, right)
    size = right.length
    intermediate = Array.new(size, 0.0)
    size.times do |row|
      total = 0.0
      row.times { |index| total += lower[row][index] * intermediate[index] }
      intermediate[row] = (right[row] - total) / lower[row][row]
    end
    solution = Array.new(size, 0.0)
    (size - 1).downto(0) do |row|
      total = 0.0
      (row + 1...size).each { |index| total += lower[index][row] * solution[index] }
      solution[row] = (intermediate[row] - total) / lower[row][row]
    end
    solution
  end

  def self.gradient_descent(rows, targets, lambda, rate, iterations)
    weights = Array.new(rows[0].length, 0.0)
    checkpoints = [[0, weights.dup]]
    (1..iterations).each do |iteration|
      gradient = Logistic.gradient(weights, rows, targets, lambda)
      weights = weights.each_index.map { |index| weights[index] - rate * gradient[index] }
      checkpoints << [iteration, weights.dup] if (iteration % 100).zero?
    end
    checkpoints
  end

  def self.stochastic(rows, targets, lambda, rate, batch_size, epochs, seed)
    generator = Minstd.new(seed)
    order = (0...rows.length).to_a
    weights = Array.new(rows[0].length, 0.0)
    checkpoints = [[0, weights.dup]]
    (1..epochs).each do |epoch|
      generator.shuffle!(order)
      order.each_slice(batch_size) do |batch|
        vectors = batch.map { |index| rows[index] }
        labels = batch.map { |index| targets[index] }
        gradient = Logistic.gradient(weights, vectors, labels, lambda)
        weights = weights.each_index.map { |index| weights[index] - rate * gradient[index] }
      end
      checkpoints << [epoch, weights.dup]
    end
    checkpoints
  end

  def self.newton(rows, targets, lambda)
    weights = Array.new(rows[0].length, 0.0)
    checkpoints = [[0, weights.dup]]
    (1..10).each do |iteration|
      gradient = Logistic.gradient(weights, rows, targets, lambda)
      lower = cholesky(Logistic.hessian(weights, rows, lambda))
      step = solve(lower, gradient)
      weights = weights.each_index.map { |index| weights[index] - step[index] }
      checkpoints << [iteration, weights.dup]
    end
    checkpoints
  end
end
