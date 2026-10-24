module RationalGeometry
  module_function

  def along(first, second, position)
    [first[0] + position * (second[0] - first[0]),
     first[1] + position * (second[1] - first[1])]
  end

  def cross(origin, first, second)
    (first[0] - origin[0]) * (second[1] - origin[1]) -
      (first[1] - origin[1]) * (second[0] - origin[0])
  end

  def point_key(point)
    [point[1], point[0]]
  end

  def fraction_text(value)
    rational = Rational(value)
    rational.denominator == 1 ? rational.numerator.to_s : "#{rational.numerator}/#{rational.denominator}"
  end

  def point_text(point)
    "(#{fraction_text(point[0])},#{fraction_text(point[1])})"
  end

  def segment_text(first, second)
    "#{point_text(first)}-#{point_text(second)}"
  end

  def real(value)
    rational = Rational(value)
    rational.numerator.to_f / rational.denominator.to_f
  end
end
