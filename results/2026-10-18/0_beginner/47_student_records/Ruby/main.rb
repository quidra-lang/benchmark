students = [['Tanaka', [78, 85, 94]], ['Suzuki', [88, 74, 82]], ['Yamada', [65, 90, 71]], ['Ito', [80, 79, 85]], ['Kato', [92, 88, 95]], ['Mori', [70, 62, 78]]]
records = students.map { |name, scores| [name, scores.sum] }.sort_by { |name, total| [-total, name] }
previous = nil
rank = 0
records.each_with_index do |(name, total), i|
  rank = i + 1 if total != previous
  average = total.fdiv(3)
  puts format('%d. %s total=%d average=%.2f', rank, name, total, average)
  previous = total
end
