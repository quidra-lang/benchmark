module Report
  POLICY_SYMBOLS = "^>v<"
  module_function

  def fixed_text(value)
    whole, fraction = value.abs.divmod(10_000)
    format("%s%d.%04d", value.negative? ? "-" : "", whole, fraction)
  end

  def average_text(total, count)
    fixed_text((10_000 * total).div(count))
  end

  def cell_text(world, cell)
    cell.divmod(world.cols).join(",")
  end

  def cells_text(world, cells)
    cells.map { |cell| cell_text(world, cell) }.join(" ")
  end

  def grid_lines(world, fields, separator = "")
    Array.new(world.rows) do |row|
      Array.new(world.cols) do |col|
        cell = row * world.cols + col
        state = world.state_index[cell]
        state.nil? ? world.kinds[cell] : fields[state]
      end.join(separator)
    end
  end

  def value_grid(world, values)
    grid_lines(world, values.map { |value| fixed_text(value) }, " ")
  end

  def policy_grid(world, policy)
    grid_lines(world, policy.map { |action| POLICY_SYMBOLS[action] })
  end

  def q_table_rows(world, name, q_values, visits)
    world.states.each_with_index.flat_map do |cell, state|
      row, col = cell.divmod(world.cols)
      ACTION_LETTERS.each_with_index.map do |letter, action|
        count = visits.nil? ? "-" : visits[state][action]
        [name, row, col, letter, fixed_text(q_values[state][action]), count].join(",")
      end
    end
  end

  def join_parts(parts)
    parts.each_with_object([]) do |part, lines|
      lines << "" unless lines.empty?
      lines.concat(part)
    end
  end

  def write_lines(path, lines)
    File.binwrite(path, lines.join("\n") + "\n")
  end
end
