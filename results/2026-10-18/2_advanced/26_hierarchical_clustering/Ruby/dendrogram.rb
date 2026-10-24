# frozen_string_literal: true

module Dendrogram
  PRIORITY = { ' ' => 0, ':' => 1, '-' => 2, '|' => 3, '+' => 4 }.freeze

  def self.leaf_order(merges, count)
    minima = (0...count).to_a
    merges.each { |a, b, _height, _size| minima << [minima[a], minima[b]].min }
    order = []
    stack = [2 * count - 2]
    until stack.empty?
      node = stack.pop
      if node < count
        order << node
      else
        a, b = merges[node - count]
        upper, lower = minima[a] < minima[b] ? [a, b] : [b, a]
        stack << lower << upper
      end
    end
    order
  end

  def self.column(height, maximum, width)
    (height / maximum * width).floor
  end

  def self.mark(grid, row, column, character)
    grid[row][column] = character if PRIORITY[character] > PRIORITY[grid[row][column]]
  end

  def self.draw(merges, ids, labels, order, width, cuts)
    count = ids.length
    maximum = merges.map { |merge| merge[2] }.max
    grid = Array.new(count) { Array.new(width + 1, ' ') }
    cuts.each do |height|
      x = column(height, maximum, width)
      count.times { |row| mark(grid, row, x, ':') } if x <= width
    end
    anchors = Array.new(2 * count - 1)
    order.each_with_index { |leaf, row| anchors[leaf] = row }
    columns = Array.new(2 * count - 1, 0)
    merges.each_with_index do |(a, b, height, _size), step|
      node = count + step
      first, last = [anchors[a], anchors[b]].minmax
      anchors[node] = (first + last) / 2
      x = columns[node] = column(height, maximum, width)
      mark(grid, first, x, '+')
      mark(grid, last, x, '+')
      (first + 1).upto(last - 1) { |row| mark(grid, row, x, '|') }
      [a, b].each do |child|
        left = child < count ? 0 : columns[child] + 1
        left.upto(x - 1) { |position| mark(grid, anchors[child], position, '-') }
      end
    end
    id_width = ids.map(&:length).max
    label_width = labels.map(&:length).max
    rows = order.each_with_index.map do |leaf, row|
      "#{ids[leaf].ljust(id_width)} #{labels[leaf].ljust(label_width)} #{grid[row].join}".rstrip
    end
    scale = (0..width).map { |x| (x % 10).zero? ? '+' : '-' }.join
    rows << ' ' * (id_width + label_width + 2) + scale
  end
end
