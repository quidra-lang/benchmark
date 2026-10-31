require_relative 'tableau'

module Simplex
  def self.phase(tableau, costs, candidates, objective)
    iterations, lines = 0, []
    loop do
      reduced = tableau.reduced(costs)
      entering = candidates.find { |column| reduced[column] < 0 }
      return {iterations: iterations, lines: lines, unbounded: nil} unless entering
      eligible = tableau.basic.each_index.select { |row| tableau.values[row][entering] > 0 }
      if eligible.empty?
        return {iterations: iterations, lines: lines, unbounded: entering}
      end
      row = eligible.min_by { |i| [tableau.beta[i] / tableau.values[i][entering], tableau.basic[i]] }
      ratio = tableau.beta[row] / tableau.values[row][entering]
      leaving = tableau.columns[tableau.basic[row]]
      tableau.pivot(row, entering)
      iterations += 1
      lines << "PIVOT #{iterations} enter #{tableau.columns[entering]} reduced #{Q.f(reduced[entering])} leave #{leaving} row #{tableau.rows[row]} ratio #{Q.f(ratio)} objective #{Q.f(objective.call(tableau.phase_value(costs)))}"
    end
  end
end
