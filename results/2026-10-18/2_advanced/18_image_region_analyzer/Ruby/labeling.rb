# frozen_string_literal: true

module Labeling
  Result = Struct.new(:labels, :groups, :provisional, keyword_init: true)
  PREVIOUS = { 4 => [[-1, 0], [0, -1]],
               8 => [[-1, 0], [-1, -1], [0, -1], [1, -1]] }.freeze

  module_function

  def root(parent, label)
    while parent[label] != label
      parent[label] = parent[parent[label]]
      label = parent[label]
    end
    label
  end

  def label(mask, width, height, connectivity)
    labels = Array.new(mask.length, 0)
    parent = [0]
    mask.each_index do |index|
      next unless mask[index]

      x, y = index % width, index.div(width)
      previous = PREVIOUS[connectivity].filter_map do |dx, dy|
        nx, ny = x + dx, y + dy
        next unless nx >= 0 && nx < width && ny >= 0 && ny < height

        value = labels[ny * width + nx]
        value if value > 0
      end
      if previous.empty?
        labels[index] = parent.length
        parent << parent.length
      else
        chosen = previous.min
        labels[index] = chosen
        previous.each do |other|
          first, second = root(parent, chosen), root(parent, other)
          parent[[first, second].max] = [first, second].min
        end
      end
    end
    numbering = {}
    groups = []
    labels.each_index do |index|
      next if labels[index].zero?

      representative = root(parent, labels[index])
      unless numbering.key?(representative)
        numbering[representative] = groups.length + 1
        groups << []
      end
      number = numbering[representative]
      labels[index] = number
      groups[number - 1] << index
    end
    Result.new(labels: labels, groups: groups, provisional: parent.length - 1)
  end

  def components(mask, width, height, connectivity)
    label(mask, width, height, connectivity).groups
  end

  def bitquad(mask, width, height, connectivity)
    one = 0
    three = 0
    diagonal = 0
    (-1...height).each do |y|
      (-1...width).each do |x|
        values = [[x, y], [x + 1, y], [x, y + 1], [x + 1, y + 1]].map do |px, py|
          px >= 0 && px < width && py >= 0 && py < height && mask[py * width + px]
        end
        count = values.count(true)
        one += 1 if count == 1
        three += 1 if count == 3
        if count == 2 && ((values[0] && values[3]) || (values[1] && values[2]))
          diagonal += 1
        end
      end
    end
    (one - three + (connectivity == 4 ? 2 * diagonal : -2 * diagonal)).div(4)
  end
end
