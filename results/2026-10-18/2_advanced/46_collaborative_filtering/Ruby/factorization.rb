require_relative 'evaluation'

# Deterministic initialization, SGD, and ALS with the specified Cholesky solver.
module Factorization
  class Generator
    def initialize(seed)
      @state = seed
    end

    def draw
      @state = (48_271 * @state) % 2_147_483_647
    end

    def factor
      ((draw % 2001) - 1000).to_f / 10_000
    end
  end

  Model = Struct.new(:mean, :users, :items, :user_bias, :item_bias) do
    def predict(user, item)
      ((mean + user_bias[user]) + item_bias[item]) + Factorization.dot(users[user], items[item])
    end
  end

  module_function

  def dot(left, right)
    total = 0.0
    left.each_index { |index| total += left[index] * right[index] }
    total
  end

  def train_svd(data)
    params = data.params
    random = Generator.new(params[:seed])
    factors = params[:factors]
    users = data.users.to_h { |user| [user, Array.new(factors) { random.factor }] }
    items = data.items.to_h { |item| [item, Array.new(factors) { random.factor }] }
    user_bias = data.users.to_h { |user| [user, 0.0] }
    item_bias = data.items.to_h { |item| [item, 0.0] }
    model = Model.new(data.mean, users, items, user_bias, item_bias)
    order = (0...data.training.size).to_a
    rate, regularization = params.values_at(:learning_rate, :regularization)
    log = []
    1.upto(params[:epochs]) do |epoch|
      (order.size - 1).downto(1) do |position|
        other = random.draw % (position + 1)
        order[position], order[other] = order[other], order[position]
      end
      order.each do |position|
        user, item, rating = data.training[position]
        error = rating - model.predict(user, item)
        user_bias[user] += rate * (error - regularization * user_bias[user])
        item_bias[item] += rate * (error - regularization * item_bias[item])
        factors.times do |factor|
          a = users[user][factor]
          b = items[item][factor]
          users[user][factor] = a + rate * (error * b - regularization * a)
          items[item][factor] = b + rate * (error * a - regularization * b)
        end
      end
      log << ['SVD', epoch, Evaluation.training_rmse(data.training, &model.method(:predict))]
    end
    [model, log]
  end

  def cholesky_solve(matrix, target)
    size = target.size
    lower = Array.new(size) { Array.new(size, 0.0) }
    size.times do |row|
      0.upto(row) do |column|
        total = 0.0
        column.times { |index| total += lower[row][index] * lower[column][index] }
        remainder = matrix[row][column] - total
        lower[row][column] = row == column ? Math.sqrt(remainder) : remainder / lower[column][column]
      end
    end
    intermediate = Array.new(size, 0.0)
    size.times do |row|
      total = 0.0
      row.times { |index| total += lower[row][index] * intermediate[index] }
      intermediate[row] = (target[row] - total) / lower[row][row]
    end
    solution = Array.new(size, 0.0)
    (size - 1).downto(0) do |row|
      total = 0.0
      (row + 1...size).each { |index| total += lower[index][row] * solution[index] }
      solution[row] = (intermediate[row] - total) / lower[row][row]
    end
    solution
  end

  def fit_vector(observations, factors, regularization)
    matrix = Array.new(factors) { Array.new(factors, 0.0) }
    target = Array.new(factors, 0.0)
    observations.each do |vector, residual|
      factors.times do |row|
        target[row] += residual * vector[row]
        factors.times { |column| matrix[row][column] += vector[row] * vector[column] }
      end
    end
    factors.times { |row| matrix[row][row] += regularization * observations.size }
    cholesky_solve(matrix, target)
  end

  def train_als(data, user_bias, item_bias)
    params = data.params
    factors = params[:factors]
    random = Generator.new(params[:seed])
    items = data.items.to_h { |item| [item, Array.new(factors) { random.factor }] }
    users = {}
    residuals = data.training.to_h do |user, item, rating, _time|
      [[user, item], rating - ((data.mean + user_bias[user]) + item_bias[item])]
    end
    model = Model.new(data.mean, users, items, user_bias, item_bias)
    log = []
    1.upto(params[:als_iterations]) do |iteration|
      data.users.each do |user|
        observations = data.by_user[user].keys.map { |item| [items[item], residuals[[user, item]]] }
        users[user] = fit_vector(observations, factors, params[:als_reg])
      end
      data.items.each do |item|
        observations = data.by_item[item].keys.map { |user| [users[user], residuals[[user, item]]] }
        items[item] = fit_vector(observations, factors, params[:als_reg])
      end
      log << ['ALS', iteration, Evaluation.training_rmse(data.training, &model.method(:predict))]
    end
    [model, log]
  end
end
