module KDTree
  class Node
    attr_accessor :point, :axis, :left, :right

    def initialize(point, axis, left = nil, right = nil)
      @point, @axis, @left, @right = point, axis, left, right
    end
  end

  module_function

  def key(point, axis)
    id, x, y = point
    axis.zero? ? [x, y, id] : [y, x, id]
  end

  def less?(first, second, axis)
    (key(first, axis) <=> key(second, axis)).negative?
  end

  def build(points, depth = 0)
    return nil if points.empty?

    axis = depth % 2
    ordered = points.sort_by { |point| key(point, axis) }
    middle = ordered.length / 2
    Node.new(ordered[middle], axis,
             build(ordered[0...middle], depth + 1),
             build(ordered[(middle + 1)..], depth + 1))
  end

  def insert(root, point)
    return Node.new(point, 0) unless root

    node = root
    loop do
      side = less?(point, node.point, node.axis) ? :left : :right
      child = node.public_send(side)
      unless child
        node.public_send("#{side}=", Node.new(point, 1 - node.axis))
        return root
      end
      node = child
    end
  end

  def minimum(root, axis)
    best = nil
    pending = [root]
    until pending.empty?
      node = pending.pop
      if node.axis == axis && node.left
        pending << node.left
        next
      end
      best = node.point if best.nil? || less?(node.point, best, axis)
      if node.axis != axis
        pending << node.right if node.right
        pending << node.left if node.left
      end
    end
    best
  end

  def delete(root, point)
    parent = side = nil
    node = root
    # A replacement leaves one descendant deletion, so a single walk suffices.
    while node
      if node.point[0] != point[0]
        parent = node
        side = less?(point, node.point, node.axis) ? :left : :right
        node = node.public_send(side)
      elsif node.right
        point = minimum(node.right, node.axis)
        node.point = point
        parent, side, node = node, :right, node.right
      elsif node.left
        point = minimum(node.left, node.axis)
        node.point = point
        node.right = node.left
        node.left = nil
        parent, side, node = node, :right, node.right
      else
        return nil unless parent

        parent.public_send("#{side}=", nil)
        return root
      end
    end
    root
  end
end
