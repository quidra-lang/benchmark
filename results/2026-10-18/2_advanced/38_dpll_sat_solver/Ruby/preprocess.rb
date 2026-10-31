require 'set'

module Preprocess
  module_function

  def simplify(variables, original, use_pure)
    working = []
    fixed = {}
    records = %i[tautology unit subsumed pure].to_h { |kind| [kind, []] }
    counts = %i[tautologies duplicate_literals unit_fixed unit_removed subsumed pure_fixed pure_removed].to_h { |key| [key, 0] }
    original.each_with_index do |clause, index|
      literals = clause.to_set
      if clause.any? { |literal| literals.include?(-literal) }
        counts[:tautologies] += 1
        records[:tautology] << index + 1
      else
        reduced = clause.uniq
        counts[:duplicate_literals] += clause.length - reduced.length
        working << [index + 1, reduced]
      end
    end

    empty_clause = nil
    loop do
      empty = working.find { |_, clause| clause.empty? }
      if empty
        empty_clause = empty[0]
        break
      end
      unit_clause = working.find { |_, clause| clause.length == 1 }
      break unless unit_clause
      unit = unit_clause[1][0]
      fixed[unit.abs] = unit.positive?
      counts[:unit_fixed] += 1
      working = working.filter_map do |number, clause|
        if clause.include?(unit)
          records[:unit] << number
          counts[:unit_removed] += 1
          nil
        else
          [number, clause.reject { |literal| literal == -unit }]
        end
      end
    end

    unless empty_clause
      sets = working.map { |_, clause| clause.to_set }
      before = working
      working = before.each_with_index.filter_map do |pair, b|
        redundant = before.each_index.any? do |a|
          a != b && (before[a][1].length < pair[1].length || a < b) && sets[a].subset?(sets[b])
        end
        if redundant
          records[:subsumed] << pair[0]
          nil
        else
          pair
        end
      end
      counts[:subsumed] = records[:subsumed].length
      if use_pure
        loop do
          present = working.flat_map { |_, clause| clause }.to_set
          pure = present.select { |literal| !present.include?(-literal) }.to_set
          break if pure.empty?
          pure.each { |literal| fixed[literal.abs] = literal.positive? }
          counts[:pure_fixed] += pure.length
          working = working.reject do |number, clause|
            remove = clause.any? { |literal| pure.include?(literal) }
            if remove
              records[:pure] << number
              counts[:pure_removed] += 1
            end
            remove
          end
        end
      end
    end
    counts[:removed] = counts.values_at(:tautologies, :unit_removed, :subsumed, :pure_removed).sum
    records.each_value(&:sort!)
    {clauses: working.map(&:last), fixed: fixed, active: (1..variables).reject { |v| fixed.key?(v) },
     counts: counts, records: records, empty_clause: empty_clause, pure: use_pure}
  end
end
