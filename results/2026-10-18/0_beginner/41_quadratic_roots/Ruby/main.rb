[[1, -3, -10], [-2, 5, 4], [3, 1, -2], [4, -12, 9], [1, 2, 5], [-2, 3, -4]].each do |a, b, c|
  discriminant = b * b - 4 * a * c
  if discriminant.positive?
    roots = [(-b + Math.sqrt(discriminant)) / (2 * a), (-b - Math.sqrt(discriminant)) / (2 * a)]
    result = format('x1 = %.4f, x2 = %.4f', roots.max, roots.min)
  elsif discriminant.zero?
    result = format('x = %.4f', (-b).fdiv(2 * a))
  else
    real = format('%.4f', (-b).fdiv(2 * a))
    imaginary = format('%.4f', Math.sqrt(-discriminant) / (2 * a.abs))
    result = "x = #{real} + #{imaginary}i, #{real} - #{imaginary}i"
  end
  puts "#{a} #{b} #{c}: #{result}"
end
