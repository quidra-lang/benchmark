require_relative 'gaussian'

module EM
  module_function

  def adjust(initial, type)
    weights = initial[:weights].dup
    means = initial[:means].map(&:dup)
    source = initial[:covariances]
    covariances = case type
                  when 'FULL' then source.map(&:dup)
                  when 'DIAG' then source.map { |a, _, c| [a, 0.0, c] }
                  when 'SPHERICAL' then source.map { |a, _, c| [(a + c) / 2, 0.0, (a + c) / 2] }
                  when 'TIED'
                    shared = 3.times.map do |j|
                      total = 0.0
                      weights.each_index { |k| total += weights[k] * source[k][j] }
                      total
                    end
                    Array.new(weights.length) { shared.dup }
                  end
    {weights: weights, means: means, covariances: covariances}
  end

  def expectation(points, model)
    total_loglik = 0.0
    records = points.map do |point|
      scores = model[:weights].each_index.map do |k|
        Gaussian.log_density(point, model[:weights][k], model[:means][k], model[:covariances][k])
      end
      maximum = scores.max
      exponentials = scores.map { |s| Math.exp(s - maximum) }
      normalizer = 0.0
      exponentials.each { |e| normalizer += e }
      log_density = maximum + Math.log(normalizer)
      total_loglik += log_density
      {r: exponentials.map { |e| e / normalizer }, lp: log_density}
    end
    [records, total_loglik]
  end

  def maximize(points, records, type, epsilon)
    n, k_count = points.length, records.first[:r].length
    counts, means, scatter = [], [], []
    k_count.times do |k|
      nk = sx = sy = 0.0
      points.each_with_index do |(x, y), i|
        r = records[i][:r][k]
        nk += r
        sx += r * x
        sy += r * y
      end
      counts << nk
      mx, my = sx / nk, sy / nk
      means << [mx, my]
      a = b = c = 0.0
      points.each_with_index do |(x, y), i|
        r = records[i][:r][k]
        dx, dy = x - mx, y - my
        a += r * dx * dx
        b += r * dx * dy
        c += r * dy * dy
      end
      scatter << [a, b, c]
    end
    if type == 'TIED'
      shared = 3.times.map do |j|
        total = 0.0
        scatter.each { |s| total += s[j] }
        total / n + (j == 1 ? 0.0 : epsilon)
      end
      covariances = Array.new(k_count) { shared.dup }
    else
      covariances = scatter.each_with_index.map do |(a, b, c), k|
        nk = counts[k]
        case type
        when 'FULL' then [a / nk + epsilon, b / nk, c / nk + epsilon]
        when 'DIAG' then [a / nk + epsilon, 0.0, c / nk + epsilon]
        when 'SPHERICAL'
          variance = (a / nk + c / nk) / 2 + epsilon
          [variance, 0.0, variance]
        end
      end
    end
    {weights: counts.map { |c| c / n }, means: means, covariances: covariances}
  end

  def fit(points, initial, type, iterations, epsilon)
    model = adjust(initial, type)
    records, loglik = expectation(points, model)
    trace = [loglik]
    iterations.times do
      model = maximize(points, records, type, epsilon)
      records, loglik = expectation(points, model)
      trace << loglik
    end
    {model: model, records: records, trace: trace, loglik: loglik}
  end
end
