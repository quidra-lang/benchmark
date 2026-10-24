module Dfg
  module_function

  def count(counts, first, second)
    counts.fetch([first, second], 0)
  end

  def count_follows(log)
    counts = Hash.new(0)
    log.each { |entry| entry[:trace].each_cons(2) { |a, b| counts[[a, b]] += entry[:weight] } }
    counts
  end

  def basic_relation(counts, first, second)
    forward = count(counts, first, second).positive?
    reverse = count(counts, second, first).positive?
    forward ? (reverse ? '||' : '->') : (reverse ? '<-' : '#')
  end

  def table(rows, width)
    ['    ' + (1..rows.length).map { |i| i.to_s.rjust(width) }.join] +
      rows.each_with_index.map { |row, i| (i + 1).to_s.rjust(4) + row.map { |value| value.to_s.rjust(width) }.join }
  end

  def footprint(activities, relation)
    activities.each_with_index.map { |name, i| "ACTIVITY #{i + 1} #{name}" } +
      table(activities.map { |first| activities.map { |second| relation.call(first, second) } }, 4)
  end
end
