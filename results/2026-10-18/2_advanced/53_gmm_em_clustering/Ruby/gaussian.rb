module Gaussian
  module_function

  def determinant(cov)
    a, b, c = cov
    a * c - b * b
  end

  def mahalanobis(point, mean, cov)
    a, b, c = cov
    dx, dy = point[0] - mean[0], point[1] - mean[1]
    (c * dx * dx - 2 * b * dx * dy + a * dy * dy) / determinant(cov)
  end

  def log_density(point, weight, mean, cov)
    Math.log(weight) - Math.log(2 * Math::PI) - Math.log(determinant(cov)) / 2 - mahalanobis(point, mean, cov) / 2
  end

  def eigen(cov)
    a, b, c = cov
    half = (a + c) / 2
    gap = Math.sqrt(((a - c) / 2) * ((a - c) / 2) + b * b)
    l1, l2 = half + gap, half - gap
    if b == 0
      ux, uy = a >= c ? [1.0, 0.0] : [0.0, 1.0]
    else
      vx, vy = a >= c ? [l1 - c, b] : [b, l1 - a]
      length = Math.sqrt(vx * vx + vy * vy)
      sign = vx < 0 ? -1 : 1
      ux, uy = sign * vx / length, sign * vy / length
    end
    {eigenvalues: [l1, l2], direction: [ux, uy], angle: Math.atan2(uy, ux) * 180 / Math::PI,
     axes: [Math.sqrt(l1), Math.sqrt(l2)], area: Math::PI * Math.sqrt(l1 * l2), correlation: b / Math.sqrt(a * c)}
  end

  def bhattacharyya(mean1, cov1, mean2, cov2)
    average = 3.times.map { |i| (cov1[i] + cov2[i]) / 2 }
    mahalanobis(mean2, mean1, average) / 8 + Math.log(determinant(average) / Math.sqrt(determinant(cov1) * determinant(cov2))) / 2
  end
end
