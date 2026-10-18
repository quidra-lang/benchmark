def kahn(courses, pairs)
  graph = courses.to_h { |course| [course, []] }
  indegree = courses.to_h { |course| [course, 0] }
  pairs.each do |source, target|
    graph[source] << target
    indegree[target] += 1
  end
  ready = courses.select { |course| indegree[course].zero? }.sort
  order = []
  until ready.empty?
    course = ready.shift
    order << course
    graph[course].each do |target|
      indegree[target] -= 1
      ready << target if indegree[target].zero?
    end
    ready.sort!
  end
  [order, (courses - order).sort]
end

courses1 = %w[physics algebra graphics programming statistics calculus databases algorithms]
pairs1 = [
  ['calculus', 'physics'], ['algebra', 'calculus'], ['programming', 'algorithms'],
  ['algebra', 'statistics'], ['algorithms', 'databases'], ['statistics', 'databases'],
  ['calculus', 'graphics'], ['algorithms', 'graphics'], ['physics', 'graphics']
]
courses2 = %w[music ecology art geology biology chemistry]
pairs2 = [
  ['music', 'art'], ['art', 'ecology'], ['biology', 'chemistry'],
  ['chemistry', 'ecology'], ['ecology', 'geology'], ['geology', 'chemistry']
]
order1, = kahn(courses1, pairs1)
order2, cycle = kahn(courses2, pairs2)
puts "order: #{order1.join(' -> ')}"
puts "order: #{order2.join(' -> ')}"
puts "cycle: #{cycle.join(' ')}"
