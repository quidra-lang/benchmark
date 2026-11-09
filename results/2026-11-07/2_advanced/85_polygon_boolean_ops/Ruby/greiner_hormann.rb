require 'set'
require_relative 'rings'

module GreinerHormann
  class Node
    attr_accessor :point, :side, :crossing, :entering, :next, :previous, :other

    def initialize(point, side, crossing = nil)
      @point, @side, @crossing, @entering = point, side, crossing, false
    end
  end

  class Crossing
    attr_reader :point, :first, :second

    def initialize(point)
      @point = point
      @first, @second = Node.new(point, 0, self), Node.new(point, 1, self)
      @first.other, @second.other = @second, @first
    end
  end

  class Graph
    attr_reader :crossings, :n_a, :n_b

    def initialize(first, second)
      @rings = [first, second]
      slots = @rings.map { |sequence| sequence.map { |ring| Array.new(ring.size) { [] } } }
      first.each_with_index do |ring, first_ring|
        Rings.edges(ring).each_with_index do |(a, b), first_edge|
          second.each_with_index do |other, second_ring|
            Rings.edges(other).each_with_index do |(c, d), second_edge|
              found = Intersections.crossing(a, b, c, d)
              next unless found
              t, u, point = found
              record = Crossing.new(point)
              slots[0][first_ring][first_edge] << [t, record.first]
              slots[1][second_ring][second_edge] << [u, record.second]
            end
          end
        end
      end
      @nodes, @initial_inside = [[], []], [[], []]
      @rings.each_with_index do |sequence, side|
        sequence.each_with_index do |ring, ring_index|
          nodes = []
          ring.each_with_index do |point, edge_index|
            nodes << Node.new(point, side)
            nodes.concat(slots[side][ring_index][edge_index].sort_by(&:first).map(&:last))
          end
          nodes.each_with_index do |node, index|
            node.previous, node.next = nodes[index - 1], nodes[(index + 1) % nodes.size]
          end
          state = Rings.interior?(@rings[1 - side], ring.first)
          @initial_inside[side] << state
          nodes.each do |node|
            next unless node.crossing
            node.entering = !state
            state = !state
          end
          @nodes[side] << nodes
        end
      end
      @crossings = @nodes[0].flat_map { |nodes| nodes.filter_map(&:crossing) }
      @n_a, @n_b = @initial_inside.map { |states| states.count(true) }
    end

    def traverse(invert_first, invert_second)
      inverted, visited, result = [invert_first, invert_second], Set.new, []
      @crossings.each do |start|
        next if visited.include?(start)
        points, current = [], start.first
        loop do
          visited.add(current.crossing)
          points << current.point
          forward = current.entering != inverted[current.side]
          stopped = forward ? current.next : current.previous
          until stopped.crossing
            points << stopped.point
            stopped = forward ? stopped.next : stopped.previous
          end
          break if stopped.crossing.equal?(start)
          current = stopped.other
        end
        result << points
      end
      @rings.each_with_index do |sequence, side|
        sequence.each_with_index do |ring, index|
          next if @nodes[side][index].any?(&:crossing)
          result << ring.dup if @initial_inside[side][index] != inverted[side]
        end
      end
      result
    end
  end
end
