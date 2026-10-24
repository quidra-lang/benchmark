pairs = [[1000, 'M'], [900, 'CM'], [500, 'D'], [400, 'CD'], [100, 'C'], [90, 'XC'], [50, 'L'], [40, 'XL'], [10, 'X'], [9, 'IX'], [5, 'V'], [4, 'IV'], [1, 'I']]
values = %w[I V X L C D M].zip([1, 5, 10, 50, 100, 500, 1000]).to_h
[9, 14, 49, 94, 444, 1994, 2768, 3999].each do |n|
  remaining = n
  roman = ''
  pairs.each do |value, symbol|
    while remaining >= value
      roman += symbol
      remaining -= value
    end
  end
  decoded = roman.chars.each_with_index.sum do |symbol, i|
    value = values[symbol]
    i + 1 < roman.length && value < values[roman[i + 1]] ? -value : value
  end
  puts "#{n} -> #{roman} -> #{decoded}"
end
