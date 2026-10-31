require_relative 'qr_solver'
require_relative 'inference'

module Diagnostics
  extend self
  include QRSolver
  include Inference

  def row_diagnostics(fitted, params)
    n, r = fitted.n, fitted.rank
    degrees = n - r
    sigma = Math.sqrt(fitted.rss / degrees)
    leverage_limit = params['LEVERAGE'] * r / n
    cook_limit = params['COOK'] / n
    dffits_limit = params['DFFITS'] * Math.sqrt(r.to_f / n)
    Array.new(n) do |i|
      h = fitted.leverage[i]
      residual = fitted.weighted_residual[i]
      z = residual / (sigma * Math.sqrt(1.0 - h))
      studentized = z * Math.sqrt((degrees - 1) / (degrees - z * z))
      cooks = z * z * h / (r * (1.0 - h))
      dffits = studentized * Math.sqrt(h / (1.0 - h))
      flags = ''
      flags += 'H' if h > leverage_limit
      flags += 'O' if studentized.abs > params['STUDENTIZED']
      flags += 'C' if cooks > cook_limit
      flags += 'F' if dffits.abs > dffits_limit
      deleted_sigma = sigma * Math.sqrt((degrees - z * z) / (degrees - 1))
      dfbetas = Array.new(r) do |k|
        fitted.g[i][k] * residual / (1.0 - h) /
          (deleted_sigma * Math.sqrt(fitted.variance[k]))
      end
      { standardized: z, studentized: studentized, cooks: cooks, dffits: dffits,
        flags: flags.empty? ? '-' : flags, dfbetas: dfbetas }
    end
  end

  def durbin_watson(fitted)
    residuals = fitted.weighted_residual
    numerator = total(1...fitted.n) do |i|
      (residuals[i] - residuals[i - 1]) * (residuals[i] - residuals[i - 1])
    end
    numerator / fitted.rss
  end

  def breusch_pagan(fitted, tolerance)
    squared = fitted.weighted_residual.map { |value| value * value }
    matrix = fitted.matrix.map { |row| fitted.accepted.map { |j| row[j] } }
    auxiliary = QRSolver::Fit.new(matrix, squared, Array.new(fitted.n, 1.0), tolerance)
    mean = total(squared) / fitted.n
    tss = total(squared) { |value| (value - mean) * (value - mean) }
    statistic = fitted.n * (1.0 - auxiliary.rss / tss)
    degrees = auxiliary.rank - 1
    [statistic, degrees, chi_pvalue(statistic, degrees)]
  end

  def jarque_bera(fitted)
    n = fitted.n
    mean = total(fitted.weighted_residual) / n
    centered = fitted.weighted_residual.map { |value| value - mean }
    m2 = total(centered) { |value| value * value } / n
    m3 = total(centered) { |value| value * value * value } / n
    m4 = total(centered) { |value| value * value * value * value } / n
    skewness = m3 / (m2 * Math.sqrt(m2))
    kurtosis = m4 / (m2 * m2)
    statistic = n / 6.0 * (skewness * skewness +
                          (kurtosis - 3.0) * (kurtosis - 3.0) / 4.0)
    [statistic, chi_pvalue(statistic, 2), skewness, kurtosis]
  end

  def calculate(fitted, params)
    { rows: row_diagnostics(fitted, params), dw: durbin_watson(fitted),
      bp: breusch_pagan(fitted, params['RANK_TOL']), jb: jarque_bera(fitted) }
  end
end
