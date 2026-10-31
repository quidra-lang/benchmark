coins = [1, 5, 6, 9]
amounts = [8, 11, 15, 22, 33, 40]
minimum = [0] + Array.new(amounts.max, amounts.max + 1)
(1...minimum.length).each do |amount|
  minimum[amount] = coins.select { |coin| coin <= amount }.map { |coin| minimum[amount - coin] + 1 }.min
end
ways = [1] + Array.new(amounts.max, 0)
coins.each do |coin|
  (coin...ways.length).each { |amount| ways[amount] += ways[amount - coin] }
end
amounts.each do |amount|
  remaining, greedy = amount, 0
  coins.reverse_each do |coin|
    while remaining >= coin
      remaining -= coin
      greedy += 1
    end
  end
  puts "#{amount}: min=#{minimum[amount]} greedy=#{greedy} ways=#{ways[amount]}"
end
