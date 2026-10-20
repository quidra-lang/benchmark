module FixedPoint
  S = 4096
  module_function

  def floor_div(a, b) = a.div(b)
  def mul(a, b) = (a * b).div(S)
  def isqrt(n) = Integer.sqrt(n)
end
