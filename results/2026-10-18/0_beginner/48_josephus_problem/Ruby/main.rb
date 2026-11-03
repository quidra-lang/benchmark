[[7, 3], [10, 2], [41, 3]].each do |n, k|
  people = (1..n).to_a
  removed = []
  index = 0
  until people.empty?
    index = (index + k - 1) % people.length
    removed << people.delete_at(index)
  end
  puts "n=#{n} k=#{k}: #{removed.join(' ')}"
  puts "survivor: #{removed[-1]}"
end
