# frozen_string_literal: true

module Components
  module_function

  def strong(adjacency)
    count = adjacency.length
    indices = Array.new(count)
    low = Array.new(count)
    active = Array.new(count, false)
    members = []
    groups = []
    serial = 0
    count.times do |start|
      next unless indices[start].nil?

      indices[start] = low[start] = serial
      serial += 1
      active[start] = true
      members << start
      frames = [[start, 0]]
      until frames.empty?
        vertex, cursor = frames[-1]
        if cursor < adjacency[vertex].length
          other = adjacency[vertex][cursor]
          frames[-1][1] += 1
          if indices[other].nil?
            indices[other] = low[other] = serial
            serial += 1
            active[other] = true
            members << other
            frames << [other, 0]
          elsif active[other]
            low[vertex] = [low[vertex], indices[other]].min
          end
          next
        end
        frames.pop
        if low[vertex] == indices[vertex]
          group = []
          loop do
            other = members.pop
            active[other] = false
            group << other
            break if other == vertex
          end
          groups << group.sort
        end
        unless frames.empty?
          parent = frames[-1][0]
          low[parent] = [low[parent], low[vertex]].min
        end
      end
    end
    groups.sort_by(&:first)
  end

  def reachable(adjacency, starts)
    seen = Array.new(adjacency.length, false)
    stack = starts.sort.reverse
    until stack.empty?
      vertex = stack.pop
      next if seen[vertex]

      seen[vertex] = true
      adjacency[vertex].reverse_each { |other| stack << other unless seen[other] }
    end
    seen
  end

  def distances(adjacency, starts)
    distances = Array.new(adjacency.length, -1)
    queue = starts.sort.uniq
    queue.each { |vertex| distances[vertex] = 0 }
    cursor = 0
    while cursor < queue.length
      vertex = queue[cursor]
      cursor += 1
      adjacency[vertex].each do |other|
        next unless distances[other] == -1

        distances[other] = distances[vertex] + 1
        queue << other
      end
    end
    distances
  end

  def weak(adjacency)
    seen = Array.new(adjacency.length, false)
    groups = []
    adjacency.each_index do |start|
      next if seen[start]

      group = []
      stack = [start]
      seen[start] = true
      until stack.empty?
        vertex = stack.pop
        group << vertex
        adjacency[vertex].each do |other|
          next if seen[other]

          seen[other] = true
          stack << other
        end
      end
      groups << group.sort
    end
    groups
  end
end
