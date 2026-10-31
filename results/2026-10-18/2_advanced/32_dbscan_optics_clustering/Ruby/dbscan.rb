module Density
  module DBSCAN
    module_function

    def cluster(neighbours, minimum)
      core = neighbours.map { |members| members.length >= minimum }
      labels = Array.new(neighbours.length)
      cluster = 0
      neighbours.each_index do |point|
        next unless labels[point].nil?

        unless core[point]
          labels[point] = -1
          next
        end
        labels[point] = cluster
        queue = neighbours[point].dup
        cursor = 0
        while cursor < queue.length
          other = queue[cursor]
          cursor += 1
          if labels[other] == -1
            labels[other] = cluster
          elsif labels[other].nil?
            labels[other] = cluster
            queue.concat(neighbours[other]) if core[other]
          end
        end
        cluster += 1
      end
      [labels, core]
    end
  end
end
