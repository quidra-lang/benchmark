[0, 10, 255, 1000, 43981, 65535].each do |n|
  puts "#{n}: bin=#{n.to_s(2)} oct=#{n.to_s(8)} hex=#{n.to_s(16).upcase}"
end
