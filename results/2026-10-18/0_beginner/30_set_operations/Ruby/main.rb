require 'set'

a = [12, 5, 8, 21, 5, 17, 3, 12, 9].to_set
b = [8, 14, 21, 6, 14, 3, 25, 6].to_set
{'union' => a | b, 'intersection' => a & b, 'difference' => a - b, 'symmetric difference' => a ^ b}.each do |label, result|
  puts "#{label}: #{result.sort.join(' ')}"
end
