module Association
  def self.minimum_matching(costs)
    return [] if costs.empty? || costs[0].empty?
    transposed = costs.length > costs[0].length
    matrix = transposed ? costs.transpose : costs
    rows, columns = matrix.length, matrix[0].length
    u, v = Array.new(rows + 1, 0.0), Array.new(columns + 1, 0.0)
    matched, previous = Array.new(columns + 1, 0), Array.new(columns + 1, 0)
    1.upto(rows) do |row|
      matched[0] = row
      column = 0
      distances = Array.new(columns + 1, Float::INFINITY)
      used = Array.new(columns + 1, false)
      loop do
        used[column] = true
        current_row = matched[column]
        delta, following = Float::INFINITY, 0
        1.upto(columns) do |candidate|
          next if used[candidate]
          reduced = matrix[current_row - 1][candidate - 1] - u[current_row] - v[candidate]
          if reduced < distances[candidate]
            distances[candidate] = reduced
            previous[candidate] = column
          end
          delta, following = distances[candidate], candidate if distances[candidate] < delta
        end
        0.upto(columns) do |candidate|
          if used[candidate]
            u[matched[candidate]] += delta
            v[candidate] -= delta
          else
            distances[candidate] -= delta
          end
        end
        column = following
        break if matched[column] == 0
      end
      until column == 0
        following = previous[column]
        matched[column] = matched[following]
        column = following
      end
    end
    pairs = (1..columns).filter_map { |column| [matched[column] - 1, column - 1] unless matched[column] == 0 }
    (transposed ? pairs.map { |row, column| [column, row] } : pairs).sort
  end

  def self.optimal_assignment(rows, columns, usable)
    return [] if rows == 0 || columns == 0 || usable.empty?
    penalty = ([rows, columns].min + 1) * ([1.0, usable.values.max].max + 1.0)
    costs = rows.times.map { |row| columns.times.map { |column| usable.fetch([row, column], penalty) } }
    minimum_matching(costs).select { |pair| usable.key?(pair) }
  end
end
