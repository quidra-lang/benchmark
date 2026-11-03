values = [7, 98000, 4096, 50301, 2718281, 123456789]
values.each do |value|
  digits = value.to_s
  digit_sum = digits.chars.sum(&:to_i)
  reversed = digits.reverse.to_i
  puts "#{value}: digits=#{digits.length} sum=#{digit_sum} reversed=#{reversed}"
end
