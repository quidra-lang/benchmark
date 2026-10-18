[0, 7, 999, 1000, -456789, 3141592, 9876543210].each do |n|
  groups = n.abs.to_s.reverse.scan(/.{1,3}/).join(',').reverse
  puts (n.negative? ? '-' : '') + groups
end
