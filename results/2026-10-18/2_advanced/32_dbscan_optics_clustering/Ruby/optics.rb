module Density
  module OPTICS
    module_function

    def run(points, grid, minimum)
      core = grid.neighbours.each_with_index.map do |members, point|
        if members.length >= minimum
          members.map { |other| GridIndex.distance(points[point], points[other]) }.sort[minimum - 1]
        end
      end
      reach = Array.new(points.length)
      predecessor = Array.new(points.length)
      processed = Array.new(points.length, false)
      order = []
      points.each_index do |start|
        next if processed[start]

        seeds = { start => true }
        until seeds.empty?
          point = seeds.keys.min_by { |candidate| [reach[candidate].nil? ? 1 : 0, reach[candidate] || 0, points[candidate].id] }
          seeds.delete(point)
          processed[point] = true
          order << point
          next if core[point].nil?

          grid.neighbours[point].each do |other|
            next if processed[other]

            value = [core[point], GridIndex.distance(points[point], points[other])].max
            next unless reach[other].nil? || value < reach[other]

            reach[other] = value
            predecessor[other] = point
            seeds[other] = true
          end
        end
      end
      { order: order, core: core, reach: reach, predecessor: predecessor }
    end
  end
end
