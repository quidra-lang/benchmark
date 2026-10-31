module RTree
  Entry = Struct.new(:box, :id, :child)

  class Node
    attr_accessor :level, :entries, :parent

    def initialize(level, entries = [], parent = nil)
      @level, @entries, @parent = level, entries, parent
      adopt_children
    end

    def box
      RTree.bounding_box(@entries.map(&:box))
    end

    def adopt_children
      @entries.each { |entry| entry.child.parent = self } if @level.positive?
    end
  end

  module_function

  def point_box(point)
    [point[1], point[2], point[1], point[2]]
  end

  def area(box)
    (box[2] - box[0]) * (box[3] - box[1])
  end

  def mbr(first, second)
    [[first[0], second[0]].min, [first[1], second[1]].min,
     [first[2], second[2]].max, [first[3], second[3]].max]
  end

  def bounding_box(boxes)
    boxes.reduce { |result, box| mbr(result, box) }
  end

  def enlargement(first, second)
    area(mbr(first, second)) - area(first)
  end

  def contains?(outer, inner)
    outer[0] <= inner[0] && inner[2] <= outer[2] &&
      outer[1] <= inner[1] && inner[3] <= outer[3]
  end

  def intersects?(first, second)
    first[0] <= second[2] && second[0] <= first[2] &&
      first[1] <= second[3] && second[1] <= first[3]
  end

  def overlap(first, second)
    width = [first[2], second[2]].min - [first[0], second[0]].max
    height = [first[3], second[3]].min - [first[1], second[1]].max
    width.positive? && height.positive? ? width * height : 0
  end

  class Tree
    attr_accessor :root
    attr_reader :maximum, :minimum

    def initialize(maximum, minimum)
      @maximum, @minimum = maximum, minimum
      @root = Node.new(0)
    end

    def choose_subtree(box, level)
      node = @root
      while node.level > level
        entry, = node.entries.each_with_index.min_by do |candidate, index|
          [RTree.enlargement(candidate.box, box), RTree.area(candidate.box), index]
        end
        node = entry.child
      end
      node
    end

    def split(node)
      entries = node.entries
      best_waste = seeds = nil
      entries.each_index do |first|
        ((first + 1)...entries.length).each do |second|
          a, b = entries[first].box, entries[second].box
          waste = RTree.area(RTree.mbr(a, b)) - RTree.area(a) - RTree.area(b)
          if best_waste.nil? || waste > best_waste
            best_waste = waste
            seeds = [first, second]
          end
        end
      end
      first, second = seeds
      group1, group2 = [entries[first]], [entries[second]]
      box1, box2 = entries[first].box, entries[second].box
      rest = entries.each_with_index.filter_map { |entry, index| entry unless seeds.include?(index) }
      until rest.empty?
        if group1.length + rest.length == @minimum
          group1.concat(rest)
          break
        elsif group2.length + rest.length == @minimum
          group2.concat(rest)
          break
        end

        selected = 0
        greatest_difference = -1
        selected_d1 = selected_d2 = 0
        rest.each_with_index do |entry, index|
          d1 = RTree.enlargement(box1, entry.box)
          d2 = RTree.enlargement(box2, entry.box)
          difference = (d1 - d2).abs
          if difference > greatest_difference
            selected = index
            greatest_difference = difference
            selected_d1, selected_d2 = d1, d2
          end
        end
        entry = rest.delete_at(selected)
        choice1 = [selected_d1, RTree.area(box1), group1.length, 0]
        choice2 = [selected_d2, RTree.area(box2), group2.length, 1]
        if (choice1 <=> choice2).negative?
          group1 << entry
          box1 = RTree.mbr(box1, entry.box)
        else
          group2 << entry
          box2 = RTree.mbr(box2, entry.box)
        end
      end
      node.entries = group1
      node.adopt_children
      Node.new(node.level, group2, node.parent)
    end

    def insert(entry, level = 0)
      node = choose_subtree(entry.box, level)
      node.entries << entry
      entry.child.parent = node if level.positive?
      loop do
        sibling = node.entries.length > @maximum ? split(node) : nil
        parent = node.parent
        unless parent
          if sibling
            @root = Node.new(node.level + 1,
                             [Entry.new(node.box, nil, node), Entry.new(sibling.box, nil, sibling)])
          end
          return
        end
        parent.entries.find { |candidate| candidate.child.equal?(node) }.box = node.box
        if sibling
          parent.entries << Entry.new(sibling.box, nil, sibling)
          sibling.parent = parent
        end
        node = parent
      end
    end

    def find_leaf(identifier, box)
      pending = [@root]
      until pending.empty?
        node = pending.pop
        if node.level.zero?
          index = node.entries.index { |entry| entry.id == identifier }
          return [node, index] if index
        else
          node.entries.reverse_each do |entry|
            pending << entry.child if RTree.contains?(entry.box, box)
          end
        end
      end
      nil
    end

    def delete(point)
      node, index = find_leaf(point[0], RTree.point_box(point))
      node.entries.delete_at(index)
      removed = []
      until node.equal?(@root)
        parent = node.parent
        index = parent.entries.index { |entry| entry.child.equal?(node) }
        if node.entries.length < @minimum
          parent.entries.delete_at(index)
          removed << node
          node.parent = nil
        else
          parent.entries[index].box = node.box
        end
        node = parent
      end
      # Removed nodes are bottom-up; internal entries keep their child subtrees.
      removed.each do |removed_node|
        removed_node.entries.each { |entry| insert(entry, removed_node.level) }
      end
      while @root.level.positive? && @root.entries.length == 1
        @root = @root.entries[0].child
        @root.parent = nil
      end
    end
  end

  def str_root(entries, maximum)
    numbered = entries.map { |entry| [entry.id, entry] }
    level = 0
    loop do
      pages = (numbered.length + maximum - 1) / maximum
      slabs = Integer.sqrt(pages)
      slabs += 1 if slabs * slabs < pages
      numbered.sort_by! do |number, entry|
        [entry.box[0] + entry.box[2], entry.box[1] + entry.box[3], number]
      end
      nodes = []
      numbered.each_slice(slabs * maximum) do |slab|
        slab.sort_by! do |number, entry|
          [entry.box[1] + entry.box[3], entry.box[0] + entry.box[2], number]
        end
        slab.each_slice(maximum) { |group| nodes << Node.new(level, group.map(&:last)) }
      end
      return nodes[0] if nodes.length == 1

      numbered = nodes.each_with_index.map do |node, number|
        [number, Entry.new(node.box, nil, node)]
      end
      level += 1
    end
  end

  def build(entries, maximum, minimum, bulk: false)
    tree = Tree.new(maximum, minimum)
    if bulk
      tree.root = str_root(entries, maximum)
    else
      entries.each { |entry| tree.insert(entry) }
    end
    tree
  end
end
