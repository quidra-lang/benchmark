require_relative 'fixed_point'

module Vector3
  include FixedPoint
  module_function

  def add(u, v) = 3.times.map { |a| u[a] + v[a] }
  def sub(u, v) = 3.times.map { |a| u[a] - v[a] }
  def neg(u) = u.map { |a| -a }
  def dot(u, v) = u.zip(v).sum { |a, b| a * b }.div(S)
  def sc(u, k) = u.map { |a| (a * k).div(S) }
  def length(u) = isqrt(u.sum { |a| a * a })

  def norm(u)
    magnitude = length(u)
    u.map { |a| (a * S).div(magnitude) }
  end
end
