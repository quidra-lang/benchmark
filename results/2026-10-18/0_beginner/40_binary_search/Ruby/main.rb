values = [3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77]
[42, 3, 77, 31, 50, 1].each do |target|
  lo, hi, found = 0, values.length - 1, -1
  probes = []
  while lo <= hi
    mid = (lo + hi) / 2
    probes << mid
    if values[mid] == target
      found = mid
      break
    end
    values[mid] < target ? lo = mid + 1 : hi = mid - 1
  end
  result = found >= 0 ? "index #{found}" : 'not found'
  puts "#{target}: probes #{probes.join(' ')} -> #{result}"
end
