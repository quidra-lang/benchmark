module Inference
  extend self

  def log_gamma(x)
    coefficients = [76.18009172947146, -86.50532032941677, 24.01409824083091,
                    -1.231739572450155, 0.001208650973866179, -0.000005395239384953]
    t = x + 5.5
    adjustment = t - (x + 0.5) * Math.log(t)
    series = 1.000000000190015
    coefficients.each_with_index { |coefficient, j| series += coefficient / (x + (j + 1)) }
    -adjustment + Math.log(2.5066282746310005 * series / x)
  end

  def replace_small(value)
    value.abs < 1e-300 ? 1e-300 : value
  end

  def beta_fraction(a, b, x)
    c = 1.0
    d = 1.0 / replace_small(1.0 - (a + b) * x / (a + 1.0))
    h = d
    (1..1000).each do |m|
      q = m * (b - m) * x / ((a - 1.0 + 2 * m) * (a + 2 * m))
      d = 1.0 / replace_small(1.0 + q * d)
      c = replace_small(1.0 + q / c)
      h *= d * c
      q = -(a + m) * (a + b + m) * x / ((a + 2 * m) * (a + 1.0 + 2 * m))
      d = 1.0 / replace_small(1.0 + q * d)
      c = replace_small(1.0 + q / c)
      delta = d * c
      h *= delta
      break if (delta - 1.0).abs < 1e-15
    end
    h
  end

  def incomplete_beta(x, a, b)
    return 0.0 if x <= 0.0
    return 1.0 if x >= 1.0

    factor = Math.exp(log_gamma(a + b) - log_gamma(a) - log_gamma(b) +
                      a * Math.log(x) + b * Math.log(1.0 - x))
    if x < (a + 1.0) / (a + b + 2.0)
      factor * beta_fraction(a, b, x) / a
    else
      1.0 - factor * beta_fraction(b, a, 1.0 - x) / b
    end
  end

  def upper_gamma(a, x)
    return 1.0 if x <= 0.0

    factor = Math.exp(-x + a * Math.log(x) - log_gamma(a))
    if x < a + 1.0
      term = 1.0 / a
      series = term
      e = a
      1000.times do
        e += 1.0
        term *= x / e
        series += term
        break if term.abs < series.abs * 1e-15
      end
      return 1.0 - series * factor
    end
    beta = x + 1.0 - a
    c = 1.0 / 1e-300
    d = 1.0 / beta
    h = d
    (1..1000).each do |i|
      q = -i * (i - a)
      beta += 2.0
      d = 1.0 / replace_small(q * d + beta)
      c = replace_small(beta + q / c)
      delta = d * c
      h *= delta
      break if (delta - 1.0).abs < 1e-15
    end
    factor * h
  end

  def t_pvalue(t, degrees)
    incomplete_beta(degrees / (degrees + t * t), degrees / 2.0, 0.5)
  end

  def f_pvalue(statistic, numerator_df, denominator_df)
    x = denominator_df / (denominator_df + numerator_df * statistic)
    incomplete_beta(x, denominator_df / 2.0, numerator_df / 2.0)
  end

  def chi_pvalue(statistic, degrees)
    upper_gamma(degrees / 2.0, statistic / 2.0)
  end

  def t_quantile(confidence, degrees)
    lo, hi = 0.0, 1000.0
    100.times do
      mid = (lo + hi) / 2.0
      if t_pvalue(mid, degrees) > 1.0 - confidence
        lo = mid
      else
        hi = mid
      end
    end
    (lo + hi) / 2.0
  end

  def significance(pvalue)
    return '' if pvalue.nil?
    return '***' if pvalue < 0.001
    return '**' if pvalue < 0.01
    return '*' if pvalue < 0.05
    return '.' if pvalue < 0.1

    ''
  end

  def four(value)
    return 'NA' if value.nil?

    rendered = format('%.4f', value)
    rendered == '-0.0000' ? '0.0000' : rendered
  end

  def probability(value)
    return 'NA' if value.nil?

    value < 0.0001 ? '<0.0001' : four(value)
  end
end
