text = 'she sells sea shells by the sea shore'
frequencies = text.chars.tally
trees = frequencies.map do |symbol, weight|
  {weight: weight, minimum: symbol, symbol: symbol, left: nil, right: nil}
end
while trees.length > 1
  trees.sort_by! { |tree| [tree[:weight], tree[:minimum]] }
  left, right = trees.shift, trees.shift
  trees << {
    weight: left[:weight] + right[:weight],
    minimum: [left[:minimum], right[:minimum]].min,
    symbol: nil, left: left, right: right
  }
end
codes = {}
visit = lambda do |tree, prefix|
  if tree[:symbol]
    codes[tree[:symbol]] = prefix
  else
    visit.call(tree[:left], prefix + '0')
    visit.call(tree[:right], prefix + '1')
  end
end
visit.call(trees[0], '')
frequencies.keys.sort.each do |symbol|
  puts "'#{symbol}' freq=#{frequencies[symbol]} code=#{codes[symbol]}"
end
bits = frequencies.sum { |symbol, count| count * codes[symbol].length }
puts "encoded bits: #{bits}"
puts "fixed 8-bit: #{text.length * 8}"
