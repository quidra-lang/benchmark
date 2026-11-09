module QuadTree
  CHILD_NAMES = %w[NW NE SW SE].freeze

  class Node
    attr_accessor :x, :y, :size, :points, :children

    def initialize(x, y, size)
      @x, @y, @size = x, y, size
      @points = []
      @children = []
    end
  end

  module_function

  def destination(node, point)
    half = node.size / 2
    east = point[1] >= node.x + half ? 1 : 0
    south = point[2] >= node.y + half ? 2 : 0
    east + south
  end

  def split(node, capacity)
    half = node.size / 2
    node.children = [
      Node.new(node.x, node.y, half),
      Node.new(node.x + half, node.y, half),
      Node.new(node.x, node.y + half, half),
      Node.new(node.x + half, node.y + half, half)
    ]
    previous = node.points
    node.points = []
    previous.each { |point| insert(node, point, capacity) }
  end

  def insert(root, point, capacity)
    node = root
    node = node.children[destination(node, point)] until node.children.empty?
    position = node.points.bsearch_index { |other| other[0] > point[0] } || node.points.length
    node.points.insert(position, point)
    split(node, capacity) if node.points.length > capacity
  end

  def delete(root, point, capacity)
    ancestors = []
    node = root
    until node.children.empty?
      ancestors << node
      node = node.children[destination(node, point)]
    end
    node.points.delete(point)
    ancestors.reverse_each do |ancestor|
      break if ancestor.children.any? { |child| !child.children.empty? }

      points = ancestor.children.flat_map(&:points)
      break if points.length > capacity

      ancestor.points = points.sort_by(&:first)
      ancestor.children = []
    end
  end

  def build(points, world, capacity)
    root = Node.new(0, 0, world)
    points.each { |point| insert(root, point, capacity) }
    root
  end
end
