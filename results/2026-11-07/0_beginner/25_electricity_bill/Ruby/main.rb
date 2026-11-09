households = [['Sato', 85], ['Suzuki', 120], ['Takahashi', 254], ['Tanaka', 300], ['Ito', 438], ['Watanabe', 176]]
total = 0
households.each do |name, usage|
  bill = 900 + [usage, 120].min * 30 + [[usage, 300].min - 120, 0].max * 36 + [usage - 300, 0].max * 40
  total += bill
  puts "#{name}: #{usage} kWh, #{bill} yen"
end
puts "total: #{total} yen"
