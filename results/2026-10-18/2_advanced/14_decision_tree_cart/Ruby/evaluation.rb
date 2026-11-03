# frozen_string_literal: true

module Evaluation
  Step = Struct.new(:node, :left, :method, keyword_init: true)
  Route = Struct.new(:leaf, :path, :steps, keyword_init: true)

  module_function

  def leaf?(node, cuts)
    node.split.nil? || cuts.key?(node.number)
  end

  def nodes(root, cuts = {})
    result = []
    pending = [root]
    until pending.empty?
      node = pending.pop
      result << node
      pending.push(node.right, node.left) unless leaf?(node, cuts)
    end
    result
  end

  def route(root, row, cuts = {})
    node = root
    path = []
    steps = []
    loop do
      path << node
      break if leaf?(node, cuts)

      observed = row.values[node.split.attribute.index]
      if !observed.nil?
        left = node.split.left?(observed)
        method = :primary
      else
        surrogate = node.surrogates.find { |candidate| !row.values[candidate.split.attribute.index].nil? }
        if surrogate
          left = surrogate.split.left?(row.values[surrogate.split.attribute.index])
          left = !left if surrogate.direction == :right
          method = :surrogate
        else
          left = node.default_left
          method = :default
        end
      end
      steps << Step.new(node: node, left: left, method: method)
      node = left ? node.left : node.right
    end
    Route.new(leaf: node, path: path, steps: steps)
  end

  def predict(root, row, cuts = {})
    route(root, row, cuts).leaf.stats.majority
  end

  def correct(root, rows, cuts = {})
    rows.count { |row| predict(root, row, cuts) == row.klass }
  end

  def real(value, digits = 4)
    result = format("%.#{digits}f", value)
    result.start_with?('-') && result.delete('-.').to_i.zero? ? result[1..] : result
  end

  def ratio(numerator, denominator)
    return '0/0 -' if denominator.zero?

    "#{numerator}/#{denominator} #{real(numerator.to_f / denominator)}"
  end

  def fraction(numerator, denominator, digits = 4)
    return '- -' if denominator.zero?

    divisor = numerator.abs.gcd(denominator)
    "#{numerator / divisor}/#{denominator / divisor} #{real(numerator.to_f / denominator, digits)}"
  end

  def classification(title, rows, predictions, classes)
    size = classes.length
    matrix = Array.new(size) { Array.new(size, 0) }
    rows.each_with_index { |row, index| matrix[row.klass][predictions[index]] += 1 }
    correct_count = size.times.sum { |index| matrix[index][index] }
    lines = ["confusion #{title} correct #{correct_count}/#{rows.length} accuracy #{fraction(correct_count, rows.length)}",
             ['actual\\predicted', *classes].join(' ')]
    classes.each_with_index { |name, index| lines << [name, *matrix[index]].join(' ') }
    macro = 0.0
    available = 0
    classes.each_with_index do |name, index|
      true_positive = matrix[index][index]
      predicted = matrix.sum { |row| row[index] }
      actual = matrix[index].sum
      denominator = predicted + actual
      lines << "class #{name} precision #{fraction(true_positive, predicted)} recall #{fraction(true_positive, actual)} f1 #{fraction(2 * true_positive, denominator)} support #{actual}"
      unless denominator.zero?
        macro += (2 * true_positive).to_f / denominator
        available += 1
      end
    end
    lines << "macro_f1 #{real(macro / available)}"
    lines
  end
end
