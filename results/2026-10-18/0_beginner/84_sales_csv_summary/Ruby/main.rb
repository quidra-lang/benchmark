rows = [
  'date,region,product,quantity,unit_price',
  '2026-04-01,north,notebook,10,200', '2026-04-01,east,marker,6,150',
  '2026-04-01,south,eraser,25,80', '2026-04-02,west,stapler,4,600',
  '2026-04-02,north,marker,8,150', '2026-04-02,east,notebook,9,200',
  '2026-04-03,south,stapler,3,600', '2026-04-03,west,eraser,15,80',
  '2026-04-03,north,eraser,20,80', '2026-04-04,east,stapler,5,600',
  '2026-04-04,south,notebook,6,200', '2026-04-04,west,marker,8,150'
]
regions, products, dates = Hash.new(0), Hash.new(0), Hash.new(0)
total = 0
rows.drop(1).each do |line|
  date, region, product, quantity, price = line.split(',')
  quantity, price = quantity.to_i, price.to_i
  sales = quantity * price
  total += sales
  regions[region] += sales
  products[product] += quantity
  dates[date] += sales
end
puts "total: #{total}"
regions.keys.sort_by { |name| [-regions[name], name] }.each { |name| puts "#{name}: #{regions[name]}" }
products.keys.sort.each { |name| puts "#{name}: #{products[name]}" }
best = dates.keys.min_by { |date| [-dates[date], date] }
puts "best day: #{best} (#{dates[best]})"
