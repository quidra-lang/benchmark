def gcd(a, b)
  a, b = b, a % b until b.zero?
  a
end

[[48, 180], [1071, 462], [7, 91], [13, 97], [36288, 98280]].each do |a, b|
  divisor = gcd(a, b)
  multiple = a / divisor * b
  puts "gcd(#{a}, #{b}) = #{divisor}, lcm(#{a}, #{b}) = #{multiple}"
end
