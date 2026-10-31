def solve(n)
  placement = []
  count = 0
  first = nil
  visit = lambda do
    row = placement.length
    if row == n
      count += 1
      first = placement.dup if first.nil?
    else
      n.times do |column|
        conflict = placement.each_with_index.any? do |previous, r|
          previous == column || (previous - column).abs == row - r
        end
        next if conflict
        placement << column
        visit.call
        placement.pop
      end
    end
  end
  visit.call
  [count, first]
end

first_eight = nil
(4..8).each do |n|
  count, first = solve(n)
  puts "N=#{n}: #{count} solutions"
  first_eight = first if n == 8
end
first_eight.each { |column| puts '.' * column + 'Q' + '.' * (7 - column) }
