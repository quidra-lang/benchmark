state = 42
arrival = 0
free_times = [0, 0]
waits = []
(1..20).each do |customer|
  state = state * 48271 % 2147483647
  arrival += state % 5 + 1
  state = state * 48271 % 2147483647
  service = state % 7 + 2
  teller = free_times[0] <= free_times[1] ? 0 : 1
  start = [arrival, free_times[teller]].max
  ending = start + service
  free_times[teller] = ending
  wait = start - arrival
  waits << wait
  puts "customer #{customer}: arrive=#{arrival} start=#{start} end=#{ending} " +
       "teller=#{teller + 1} wait=#{wait}"
end
puts format('average wait: %.2f', waits.sum.fdiv(20))
puts "max wait: #{waits.max}"
puts "last departure: #{free_times.max}"
