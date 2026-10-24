cache = []
hits = misses = 0
'B A C B D A B E A D D C A E B'.split.each do |key|
  if cache.include?(key)
    hits += 1
    cache.delete(key)
    result = 'hit'
  else
    misses += 1
    result = 'miss'
    result += ", evict #{cache.pop}" if cache.length == 3
  end
  cache.unshift(key)
  puts "#{key}: #{result} [#{cache.join(' ')}]"
end
puts "hits: #{hits} misses: #{misses}"
