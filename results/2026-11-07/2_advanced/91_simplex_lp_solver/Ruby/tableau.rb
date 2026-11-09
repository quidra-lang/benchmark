require_relative 'rational'

class Tableau
  attr_reader :rows, :columns, :values, :beta, :basic
  def initialize(form)
    @rows, @columns = form.values_at(:row_names, :column_names)
    @values = form[:matrix].map(&:dup)
    @beta, @basic = form[:rhs].dup, form[:initial].dup
  end

  def reduced(costs)
    costs.each_index.map do |column|
      costs[column] - @basic.each_index.sum(Q::ZERO) { |row| costs[@basic[row]] * @values[row][column] }
    end
  end

  def phase_value(costs)
    @basic.each_index.sum(Q::ZERO) { |row| costs[@basic[row]] * @beta[row] }
  end

  def pivot(row, column)
    divisor = @values[row][column]
    @values[row].map! { |value| value / divisor }
    @beta[row] /= divisor
    @values.each_index do |other|
      next if other == row
      factor = @values[other][column]
      @values[other].each_index { |k| @values[other][k] -= factor * @values[row][k] }
      @beta[other] -= factor * @beta[row]
    end
    @basic[row] = column
  end

  def display(heading, costs, objective)
    lines = ["TABLEAU #{heading}", 'COLUMNS ' + @columns.join(' ')]
    @rows.each_index do |row|
      lines << "ROW #{@rows[row]} #{@columns[@basic[row]]} #{@values[row].map { |v| Q.f(v) }.join(' ')} | #{Q.f(@beta[row])}"
    end
    lines << "COST #{reduced(costs).map { |v| Q.f(v) }.join(' ')} | #{Q.f(objective.call(phase_value(costs)))}"
    lines
  end
end
