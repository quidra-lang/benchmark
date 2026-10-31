limit = 200
is_prime = Array.new(limit + 1, true)
is_prime[0] = is_prime[1] = false
(2..limit).each do |n|
  (n * 2).step(limit, n) { |multiple| is_prime[multiple] = false } if is_prime[n]
end
primes = (2..limit).select { |n| is_prime[n] }
puts "count: #{primes.length}"
primes.each_slice(10) { |row| puts row.join(' ') }
