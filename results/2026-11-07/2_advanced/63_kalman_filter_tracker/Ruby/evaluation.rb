require_relative 'association'
require_relative 'matrix'

module Evaluation
  def squared_distance(a, b)
    dx, dy = a[0] - b[0], a[1] - b[1]
    dx * dx + dy * dy
  end

  def distance(a, b)
    Math.sqrt(squared_distance(a, b))
  end

  def ospa(first, second, cutoff)
    return 0.0 if first.empty? && second.empty?
    return cutoff if first.empty? || second.empty?
    smaller, larger = first.length <= second.length ? [first, second] : [second, first]
    costs = smaller.map do |point|
      larger.map do |other|
        clipped = [cutoff, distance(point, other)].min
        clipped * clipped
      end
    end
    cost = Mat.total(Association.minimum_matching(costs).map { |row, column| costs[row][column] })
    Math.sqrt((cost + cutoff * cutoff * (larger.length - smaller.length)) / larger.length)
  end

  def continuity(labels)
    covered = groups = swaps = 0
    previous_label, previous_covered, delay = nil, false, nil
    labels.each_with_index do |label, offset|
      unless label
        previous_covered = false
        next
      end
      covered += 1
      delay ||= offset
      groups += 1 unless previous_covered
      swaps += 1 if previous_label && label != previous_label
      previous_label, previous_covered = label, true
    end
    { covered: covered, breaks: [0, groups - 1].max, swaps: swaps, delay: delay }
  end

  def real(value)
    return '-' if value.nil?
    text = format('%.4f', value)
    text == '-0.0000' ? '0.0000' : text
  end
end
