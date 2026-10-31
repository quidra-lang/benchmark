module Layers
  module_function

  def activate(kind, z)
    case kind
    when 'TANH' then Math.tanh(z)
    when 'SIGMOID' then 1.0 / (1 + Math.exp(-z))
    else z > 0 ? z : 0.0
    end
  end

  def derivative(kind, z, a)
    case kind
    when 'TANH' then 1 - a * a
    when 'SIGMOID' then a * (1 - a)
    else z > 0 ? 1.0 : 0.0
    end
  end

  def preactivation(weights, biases, inputs)
    weights.each_with_index.map do |row, j|
      total = 0.0
      row.each_with_index { |w, i| total += w * inputs[i] }
      total + biases[j]
    end
  end

  def backward_sum(weights, errors)
    weights[0].each_index.map do |i|
      total = 0.0
      weights.each_with_index { |row, j| total += row[i] * errors[j] }
      total
    end
  end

  def output(kind, z, label)
    count = z.size
    if kind == 'SOFTMAX'
      maximum = z.max
      terms = z.map { |v| Math.exp(v - maximum) }
      total = 0.0
      terms.each { |v| total += v }
      scores = terms.map { |v| v / total }
      [scores, Math.log(total) - (z[label] - maximum), scores.each_with_index.map { |v, k| v - (k == label ? 1.0 : 0.0) }]
    else
      scores = z.map { |v| activate('SIGMOID', v) }
      loss = 0.0
      errors = scores.each_with_index.map do |v, k|
        d = v - (k == label ? 1.0 : 0.0)
        loss += d * d
        2 * d * v * (1 - v) / count
      end
      [scores, loss / count, errors]
    end
  end
end
