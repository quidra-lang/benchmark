balance = 1000000
month = total_interest = total_paid = 0
while balance.positive?
  month += 1
  interest = balance / 100
  payment = [50000, balance + interest].min
  principal = payment - interest
  balance -= principal
  total_interest += interest
  total_paid += payment
  puts "month #{month}: interest=#{interest} principal=#{principal} balance=#{balance}"
end
puts "total interest: #{total_interest}"
puts "total paid: #{total_paid}"
