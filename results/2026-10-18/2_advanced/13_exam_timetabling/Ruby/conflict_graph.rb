class ConflictGraph
  attr_reader :neighbours, :vertices, :edges

  def initialize(courses, students)
    @neighbours = courses.to_h { |id, _course| [id, {}] }
    students.each_value do |ids|
      ids.combination(2) do |first, second|
        @neighbours[first][second] = @neighbours[first].fetch(second, 0) + 1
        @neighbours[second][first] = @neighbours[second].fetch(first, 0) + 1
      end
    end
    @vertices = courses.keys.select { |id| courses[id].count > 0 }.sort
    @edges = []
    @vertices.each do |first|
      @neighbours[first].keys.sort.each do |second|
        @edges << [first, second, @neighbours[first][second]] if first < second
      end
    end
  end

  def degree(id)
    @neighbours[id].length
  end

  def components
    seen = {}
    result = []
    @vertices.each do |start|
      next if seen[start]

      group = []
      stack = [start]
      seen[start] = true
      until stack.empty?
        id = stack.pop
        group << id
        @neighbours[id].each_key do |other|
          next if seen[other]

          seen[other] = true
          stack << other
        end
      end
      result << group.sort
    end
    result.sort_by { |group| [-group.length, group.first] }
  end

  def clique(candidates)
    result = []
    until candidates.empty?
      id = candidates.min_by { |course| [-degree(course), course] }
      result << id
      candidates = candidates.select { |other| @neighbours[id].key?(other) }
    end
    result
  end

  def kempe(start, first_slot, second_slot, assignment)
    seen = { start => true }
    stack = [start]
    until stack.empty?
      id = stack.pop
      @neighbours[id].each_key do |other|
        next if seen[other] || ![first_slot, second_slot].include?(assignment[other])

        seen[other] = true
        stack << other
      end
    end
    seen.keys.sort
  end

  def self.reachable?(orders, start, target)
    seen = {}
    stack = [start]
    until stack.empty?
      id = stack.pop
      return true if id == target
      next if seen[id]

      seen[id] = true
      orders.each { |first, second| stack << second if first == id && !seen[second] }
    end
    false
  end
end
