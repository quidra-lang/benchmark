# frozen_string_literal: true

module FPGrowth
  class Node
    attr_reader :item, :parent, :children
    attr_accessor :count

    def initialize(item, parent)
      @item = item
      @parent = parent
      @children = {}
      @count = 0
    end
  end

  class Tree
    attr_reader :header, :nodes, :node_count

    def initialize(base, threshold)
      support = Hash.new(0)
      base.each { |items, weight| items.each { |item| support[item] += weight } }
      @header = support.keys.select { |item| support[item] >= threshold }.sort_by { |item| [-support[item], item] }
      position = @header.each_with_index.to_h
      @nodes = @header.to_h { |item| [item, []] }
      @node_count = 0
      root = Node.new(nil, nil)
      base.each do |items, weight|
        current = root
        items.select { |item| position.key?(item) }.sort_by { |item| position[item] }.each do |item|
          unless current.children.key?(item)
            node = Node.new(item, current)
            current.children[item] = node
            @nodes[item] << node
            @node_count += 1
          end
          current = current.children[item]
          current.count += weight
        end
      end
    end

    def conditional_base(item)
      @nodes.fetch(item).map do |node|
        path = []
        parent = node.parent
        until parent.item.nil?
          path << parent.item
          parent = parent.parent
        end
        [path.reverse, node.count]
      end
    end
  end

  def self.mine(baskets, threshold, maximum)
    whole = Tree.new(baskets.map { |basket| [basket.to_a, 1] }, threshold)
    statistics = { header: whole.header.length, nodes: whole.node_count, conditional_trees: 0, conditional_nodes: 0 }
    result = {}
    stack = [[whole, []]]
    until stack.empty?
      tree, suffix = stack.pop
      tree.header.reverse_each do |item|
        pattern = (suffix + [item]).sort
        result[pattern] = tree.nodes.fetch(item).sum(&:count)
        next if pattern.length == maximum

        conditional = Tree.new(tree.conditional_base(item), threshold)
        next if conditional.node_count.zero?

        statistics[:conditional_trees] += 1
        statistics[:conditional_nodes] += conditional.node_count
        stack << [conditional, pattern]
      end
    end
    statistics[:itemsets] = result.length
    [result, statistics]
  end
end
