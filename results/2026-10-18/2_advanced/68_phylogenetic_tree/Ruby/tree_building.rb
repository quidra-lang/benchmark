require 'set'

module TreeBuilding
  class Tree
    attr_accessor :adjacent, :next_node, :negative
    attr_reader :size
    def initialize(size, taxa)
      @size, @next_node, @negative = size, size, 0
      @adjacent = taxa.to_h { |taxon| [taxon, {}] }
    end
    def internal
      node = @next_node
      @next_node += 1
      @adjacent[node] = {}
      node
    end
    def connect(a, b, length = 0.0)
      @adjacent[a][b] = @adjacent[b][a] = length
    end
    def disconnect(a, b)
      length = @adjacent[a].delete(b)
      @adjacent[b].delete(a)
      length
    end
    def copy
      result = Tree.new(@size, [])
      result.adjacent = @adjacent.transform_values(&:dup)
      result.next_node, result.negative = @next_node, @negative
      result
    end
    def taxa = @adjacent.keys.select { |node| node < @size }.sort
    def internal_nodes = @adjacent.keys.select { |node| node >= @size }.sort
    def edges
      @adjacent.keys.sort.flat_map do |a|
        @adjacent[a].keys.sort.filter_map { |b| [a, b, @adjacent[a][b]] if a < b }
      end
    end
    def rooted(outgroup) = Rooted.new(self, outgroup)
  end

  class Rooted
    attr_reader :tree, :outgroup, :root, :parents, :children, :masks, :order, :ingroup
    def initialize(tree, outgroup)
      @tree, @outgroup = tree, outgroup
      @root = tree.adjacent[outgroup].keys.first
      @parents, @children, @masks, @order = {}, {}, {}, []
      visit(@root, nil)
      @ingroup = @masks[@root] ^ (1 << outgroup)
    end
    def visit(node, parent)
      @parents[node] = parent
      @order << node
      @children[node] = @tree.adjacent[node].keys.reject { |child| child == parent }
      mask = node < @tree.size ? 1 << node : 0
      @children[node].each do |child|
        visit(child, node)
        mask |= @masks[child]
      end
      @masks[node] = mask
    end
    def splits = @tree.internal_nodes.reject { |node| node == @root }.map { |node| @masks[node] }.to_set
    def branch_lengths
      @order.drop(1).to_h do |node|
        [node == @outgroup ? @ingroup : @masks[node], @tree.adjacent[node][@parents[node]]]
      end
    end
  end

  def self.star(size, taxa)
    tree = Tree.new(size, taxa)
    root = tree.internal
    taxa.each { |taxon| tree.connect(root, taxon) }
    tree
  end

  def self.neighbor_joining(matrix, taxa)
    active = taxa.to_a.dup
    tree = Tree.new(matrix.size, active)
    distances = active.to_h { |a| [a, active.to_h { |b| [b, matrix[a][b]] }] }
    while active.size >= 4
      r = active.size
      totals = active.to_h do |a|
        total = 0.0
        active.each { |b| total += distances[a][b] if a != b }
        [a, total]
      end
      selected, minimum = nil, nil
      active.combination(2) do |a, b|
        q = (r - 2) * distances[a][b] - totals[a] - totals[b]
        selected, minimum = [a, b], q if minimum.nil? || q < minimum
      end
      a, b = selected
      node = tree.internal
      distance = distances[a][b]
      length = distance / 2.0 + (totals[a] - totals[b]) / (2.0 * (r - 2))
      tree.connect(a, node, length)
      tree.connect(b, node, distance - length)
      remaining = active.reject { |other| other == a || other == b }
      distances[node] = {}
      remaining.each do |other|
        distances[node][other] = distances[other][node] =
          (distances[a][other] + distances[b][other] - distance) / 2.0
      end
      active = remaining << node
    end
    a, b, c = active
    node = tree.internal
    ab, ac, bc = distances[a][b], distances[a][c], distances[b][c]
    tree.connect(a, node, (ab + ac - bc) / 2.0)
    tree.connect(b, node, (ab + bc - ac) / 2.0)
    tree.connect(c, node, (ac + bc - ab) / 2.0)
    tree.edges.each do |first, second, length|
      next unless length < 0
      tree.connect(first, second, 0.0)
      tree.negative += 1
    end
    tree
  end

  def self.path_distances(tree, start, unit: false)
    distances = { start => unit ? 0 : 0.0 }
    stack = [[start, nil]]
    until stack.empty?
      node, parent = stack.pop
      tree.adjacent[node].each do |neighbor, length|
        next if neighbor == parent
        distances[neighbor] = distances[node] + (unit ? 1 : length)
        stack << [neighbor, node]
      end
    end
    distances
  end

  def self.patristic_matrix(tree)
    matrix = Array.new(tree.size) { Array.new(tree.size, 0.0) }
    tree.taxa.each do |a|
      paths = path_distances(tree, a)
      tree.taxa.each { |b| matrix[a][b] = matrix[b][a] = paths[b] if a < b }
    end
    matrix
  end
end
