values = [47, 12, 85, 33, 6, 71, 29, 58, 90, 14]
merge_sort = lambda do |left, right|
  next 0 if left == right
  middle = (left + right) / 2
  inversions = merge_sort.call(left, middle) + merge_sort.call(middle + 1, right)
  a, b = values[left..middle], values[middle + 1..right]
  i = j = 0
  merged = []
  while i < a.length && j < b.length
    if a[i] < b[j]
      merged << a[i]
      i += 1
    else
      merged << b[j]
      j += 1
      inversions += a.length - i
    end
  end
  merged.concat(a.drop(i)).concat(b.drop(j))
  values[left..right] = merged
  puts "merge [#{left}..#{right}]: #{merged.join(' ')}"
  inversions
end
inversions = merge_sort.call(0, values.length - 1)
puts "sorted: #{values.join(' ')}"
puts "inversions: #{inversions}"
