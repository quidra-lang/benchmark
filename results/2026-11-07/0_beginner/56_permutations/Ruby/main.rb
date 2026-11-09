letters = 'ABCD'
used = Array.new(letters.length, false)
count = 0
visit = lambda do |prefix|
  if prefix.length == letters.length
    count += 1
    puts "#{count}: #{prefix}"
  else
    letters.each_char.with_index do |letter, i|
      next if used[i]
      used[i] = true
      visit.call(prefix + letter)
      used[i] = false
    end
  end
end
visit.call('')
