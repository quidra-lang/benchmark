def fixed(value)
  format('%.4f', value.round(4, half: :up))
end

[[1, -3, -10], [-2, 5, 4], [3, 1, -2], [4, -12, 9], [1, 2, 5], [-2, 3, -4]].each do |a, b, c|
  discriminant = b * b - 4 * a * c
  if discriminant.positive?
    roots = [(-b + Math.sqrt(discriminant)) / (2 * a), (-b - Math.sqrt(discriminant)) / (2 * a)]
    result = "x1 = #{fixed(roots.max)}, x2 = #{fixed(roots.min)}"
  elsif discriminant.zero?
    result = "x = #{fixed((-b).fdiv(2 * a))}"
  else
    real = fixed((-b).fdiv(2 * a))
    imaginary = fixed(Math.sqrt(-discriminant) / (2 * a.abs))
    result = "x = #{real} + #{imaginary}i, #{real} - #{imaginary}i"
  end
  puts "#{a} #{b} #{c}: #{result}"
end
