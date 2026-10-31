require_relative 'rational'
require_relative 'lp_parser'
require_relative 'tableau'
require_relative 'simplex'
require_relative 'branch_bound'

def dot(left, right)
  left.each_index.sum(Q::ZERO) { |index| left[index] * right[index] }
end

def coefficients(terms, variables)
  values = variables.to_h { |name| [name, Q::ZERO] }
  terms.each { |name, coefficient| values[name] += coefficient }
  variables.map { |name| values[name] }
end

def content_check(parsed)
  return parsed if parsed[:error]
  variables = []
  ([parsed[:objective]] + parsed[:constraints].map { |row| row[:terms] }).each do |terms|
    terms.each { |name, _| variables << name unless variables.include?(name) }
  end
  model = {name: parsed[:name], error: nil, direction: parsed[:direction], variables: variables,
           constraints: parsed[:constraints], costs: coefficients(parsed[:objective], variables),
           matrix: parsed[:constraints].map { |row| coefficients(row[:terms], variables) },
           rhs: parsed[:constraints].map { |row| row[:rhs] },
           comparisons: parsed[:constraints].map { |row| row[:op] },
           lower: Array.new(variables.length, Q::ZERO), upper: Array.new(variables.length),
           integer: Array.new(variables.length, false)}
  seen = {}
  parsed[:constraints].each do |row|
    if seen[row[:name]]
      model[:error] = [row[:line], "duplicate constraint #{row[:name]}"]
      return model
    end
    seen[row[:name]] = true
  end
  parsed[:bounds].each do |bound|
    index = variables.index(bound[:name])
    unless index
      model[:error] = [bound[:line], "unknown variable #{bound[:name]}"]
      return model
    end
    model[:lower][index] = bound[:lower] if %i[both lower].include?(bound[:kind])
    model[:upper][index] = bound[:upper] if %i[both upper].include?(bound[:kind])
    lower, upper = model[:lower][index], model[:upper][index]
    if lower && upper && lower > upper
      model[:error] = [bound[:line], "inconsistent bounds #{bound[:name]}"]
      return model
    end
  end
  %i[integers binaries].each do |kind|
    parsed[kind].each do |line, names|
      names.each do |name|
        index = variables.index(name)
        unless index
          model[:error] = [line, "unknown variable #{name}"]
          return model
        end
        model[:integer][index] = true
        if kind == :binaries
          model[:lower][index], model[:upper][index] = Q::ZERO, Q::ONE
        else
          lower, upper = model[:lower][index], model[:upper][index]
          model[:lower][index] = Rational(lower.ceil) if lower
          model[:upper][index] = Rational(upper.floor) if upper
          if model[:lower][index] && model[:upper][index] && model[:lower][index] > model[:upper][index]
            model[:error] = [line, "inconsistent bounds #{name}"]
            return model
          end
        end
      end
    end
  end
  model
end

def standard_form(model, lower, upper)
  column_names, owners, directions, mappings = [], [], [], []
  model[:variables].each_with_index do |name, j|
    first = column_names.length
    if lower[j]
      kind, offset, columns, signs, names = :shift, lower[j], [first], [1], [name]
    elsif upper[j]
      kind, offset, columns, signs, names = :reflect, upper[j], [first], [-1], [name + "'"]
    else
      kind, offset, columns, signs, names = :split, Q::ZERO, [first, first + 1], [1, -1], [name + '+', name + '-']
    end
    column_names.concat(names)
    owners.concat(Array.new(columns.length, j))
    directions.concat(signs)
    mappings << {kind: kind, offset: offset, columns: columns, directions: signs, upper_row: nil}
  end
  offsets = mappings.map { |mapping| mapping[:offset] }
  row_names = model[:constraints].map { |row| row[:name] }
  matrix = model[:matrix].map { |row| owners.each_index.map { |k| directions[k] * row[owners[k]] } }
  rhs = model[:rhs].each_index.map { |i| model[:rhs][i] - dot(model[:matrix][i], offsets) }
  comparisons = model[:comparisons].dup
  mappings.each_with_index do |mapping, j|
    next unless mapping[:kind] == :shift && upper[j]
    mapping[:upper_row] = row_names.length
    row_names << model[:variables][j] + '.ub'
    row = Array.new(column_names.length, Q::ZERO)
    row[mapping[:columns].first] = Q::ONE
    matrix << row
    rhs << upper[j] - lower[j]
    comparisons << '<='
  end
  signs = Array.new(row_names.length, 1)
  row_names.each_index do |i|
    next unless rhs[i] < 0
    signs[i] = -1
    rhs[i] = -rhs[i]
    matrix[i].map! { |value| -value }
    comparisons[i] = {'<='=>'>=', '>='=>'<=', '='=>'='}[comparisons[i]]
  end
  slack, initial, artificial = Array.new(row_names.length), Array.new(row_names.length), {}
  comparisons.each_with_index do |comparison, i|
    next if comparison == '='
    slack[i] = column_names.length
    initial[i] = slack[i] if comparison == '<='
    column_names << 's:' + row_names[i]
    matrix.each_with_index { |row, t| row << Rational(t == i ? (comparison == '<=' ? 1 : -1) : 0) }
  end
  comparisons.each_with_index do |comparison, i|
    next if comparison == '<='
    column = column_names.length
    artificial[column] = true
    initial[i] = column
    column_names << 'a:' + row_names[i]
    matrix.each_with_index { |row, t| row << Rational(t == i ? 1 : 0) }
  end
  direction = model[:direction] == 'minimize' ? 1 : -1
  phase2 = owners.each_index.map { |k| direction * directions[k] * model[:costs][owners[k]] }
  phase2.concat(Array.new(column_names.length - phase2.length, Q::ZERO))
  phase1 = column_names.each_index.map { |k| artificial[k] ? Q::ONE : Q::ZERO }
  {column_names: column_names, row_names: row_names, mappings: mappings, matrix: matrix, rhs: rhs,
   signs: signs, slack: slack, artificial: artificial, initial: initial, phase1: phase1,
   phase2: phase2, constant: dot(model[:costs], offsets), direction: direction}
end

def tableau_solution(form, tableau)
  columns = Array.new(form[:column_names].length, Q::ZERO)
  tableau.basic.each_with_index { |column, i| columns[column] = tableau.beta[i] }
  form[:mappings].map do |mapping|
    change = mapping[:columns].each_index.sum(Q::ZERO) do |k|
      mapping[:directions][k] * columns[mapping[:columns][k]]
    end
    mapping[:offset] + change
  end
end

def farkas_multipliers(result)
  form, tableau = result.values_at(:form, :tableau)
  reduced = tableau.reduced(form[:phase1])
  form[:initial].each_with_index.map { |column, i| form[:signs][i] * (form[:phase1][column] - reduced[column]) }
end

def unbounded_ray(model, result)
  form, tableau, column = result.values_at(:form, :tableau, :unbounded)
  delta = Array.new(form[:column_names].length, Q::ZERO)
  delta[column] = Q::ONE
  tableau.basic.each_with_index { |basic, i| delta[basic] = -tableau.values[i][column] }
  ray = form[:mappings].map do |mapping|
    mapping[:columns].each_index.sum(Q::ZERO) { |k| mapping[:directions][k] * delta[mapping[:columns][k]] }
  end
  [ray, dot(model[:costs], ray)]
end

def solve_lp(model, lower, upper, number, level)
  form = standard_form(model, lower, upper)
  tableau = Tableau.new(form)
  lines = []
  emit = ->(required, line) { lines << line if required <= level }
  phase2_value = ->(value) { form[:constant] + form[:direction] * value }
  identity = ->(value) { value }
  display = lambda do |heading, costs, objective|
    lines.concat(tableau.display(heading, costs, objective)) if level >= 2
  end
  emit.call(0, "SOLVE node #{number} rows #{form[:row_names].length} columns #{form[:column_names].length} artificials #{form[:artificial].length}")
  form[:mappings].each_with_index do |mapping, j|
    text = "MAP #{model[:variables][j]} #{mapping[:kind]}"
    text += " #{Q.f(mapping[:offset])}" unless mapping[:kind] == :split
    text += " upper #{Q.f(upper[j])}" if mapping[:kind] == :shift && upper[j]
    emit.call(1, text)
  end
  form[:row_names].each_index { |i| emit.call(1, "FLIP #{form[:row_names][i]}") if form[:signs][i] == -1 }
  phase1_count = phase2_count = drives = redundant = 0
  infeasibility, status, unbounded = Q::ZERO, 'OPTIMAL', nil
  unless form[:artificial].empty?
    emit.call(1, 'PHASE 1')
    display.call('phase 1 start', form[:phase1], identity)
    phase = Simplex.phase(tableau, form[:phase1], form[:column_names].each_index.to_a, identity)
    phase1_count = phase[:iterations]
    phase[:lines].each { |line| emit.call(1, line) }
    infeasibility = tableau.phase_value(form[:phase1])
    emit.call(1, "PHASE 1 END objective #{Q.f(infeasibility)} iterations #{phase1_count}")
    if infeasibility > 0
      status = 'INFEASIBLE'
      display.call('final', form[:phase1], identity)
    else
      tableau.basic.each_index do |row|
        basic = tableau.basic[row]
        next unless form[:artificial][basic]
        entering = tableau.values[row].each_index.find { |k| !form[:artificial][k] && tableau.values[row][k] != 0 }
        if entering
          leaving = form[:column_names][basic]
          tableau.pivot(row, entering)
          drives += 1
          emit.call(1, "DRIVE row #{form[:row_names][row]} enter #{form[:column_names][entering]} leave #{leaving}")
        else
          redundant += 1
          emit.call(1, "REDUNDANT row #{form[:row_names][row]}")
        end
      end
    end
  end
  unless status == 'INFEASIBLE'
    emit.call(1, 'PHASE 2')
    display.call('phase 2 start', form[:phase2], phase2_value)
    candidates = form[:column_names].each_index.reject { |k| form[:artificial][k] }
    phase = Simplex.phase(tableau, form[:phase2], candidates, phase2_value)
    phase2_count = phase[:iterations]
    phase[:lines].each { |line| emit.call(1, line) }
    unbounded = phase[:unbounded]
    if unbounded
      status = 'UNBOUNDED'
      emit.call(1, "UNBOUNDED enter #{form[:column_names][unbounded]}")
    end
    emit.call(1, "PHASE 2 END objective #{Q.f(phase2_value.call(tableau.phase_value(form[:phase2])))} iterations #{phase2_count}")
    display.call('final', form[:phase2], phase2_value)
  end
  objective = status == 'OPTIMAL' ? phase2_value.call(tableau.phase_value(form[:phase2])) : nil
  emit.call(0, "RESULT #{status} objective #{Q.f(objective)} phase1 #{phase1_count} phase2 #{phase2_count} drives #{drives} redundant #{redundant}")
  {status: status, objective: objective, solution: tableau_solution(form, tableau), form: form,
   tableau: tableau, unbounded: unbounded, infeasibility: infeasibility,
   phase1: phase1_count, phase2: phase2_count, drives: drives, redundant: redundant,
   pivots: phase1_count + phase2_count + drives, lines: lines}
end

def statistics_line(model)
  sets = {matrix: model[:matrix].flatten, objective: model[:costs], rhs: model[:rhs], bounds: model[:lower] + model[:upper]}
  nonzeros = sets[:matrix].count { |value| value != 0 }
  parts = ["STATS nonzeros #{nonzeros}"]
  sets.each do |name, values|
    magnitudes = values.compact.reject(&:zero?).map(&:abs)
    parts << "#{name} #{Q.f(magnitudes.min)} #{Q.f(magnitudes.max)}"
  end
  parts.join(' ')
end

def range_endpoints(origin, changes, numerators)
  lower, upper = [], []
  changes.each_with_index do |change, i|
    lower << numerators[i] / change if change > 0
    upper << numerators[i] / change if change < 0
  end
  [lower.empty? ? nil : origin + lower.max, upper.empty? ? nil : origin + upper.min]
end

def objective_range(model, result, variable, reduced, nonbasic)
  form, tableau = result.values_at(:form, :tableau)
  h = Array.new(form[:column_names].length, Q::ZERO)
  mapping = form[:mappings][variable]
  mapping[:columns].each_with_index { |column, i| h[column] = Rational(form[:direction] * mapping[:directions][i]) }
  changes = nonbasic.map do |column|
    h[column] - tableau.basic.each_index.sum(Q::ZERO) { |i| h[tableau.basic[i]] * tableau.values[i][column] }
  end
  range_endpoints(model[:costs][variable], changes, nonbasic.map { |column| -reduced[column] })
end

def rhs_range(model, result, constraint)
  form, tableau = result.values_at(:form, :tableau)
  initial = form[:initial][constraint]
  rho = tableau.values.map { |row| form[:signs][constraint] * row[initial] }
  if tableau.basic.each_index.any? { |i| rho[i] != 0 && form[:artificial][tableau.basic[i]] }
    return [model[:rhs][constraint], model[:rhs][constraint]]
  end
  range_endpoints(model[:rhs][constraint], rho, tableau.beta.map { |value| -value })
end

def variable_status(form, basic, variable)
  mapping = form[:mappings][variable]
  if mapping[:kind] == :split
    return mapping[:columns].any? { |column| basic.include?(column) } ? 'basic' : 'zero'
  end
  if mapping[:kind] == :reflect
    return basic.include?(mapping[:columns].first) ? 'basic' : 'upper'
  end
  return 'lower' unless basic.include?(mapping[:columns].first)
  upper_row = mapping[:upper_row]
  return 'upper' if upper_row && !basic.include?(form[:slack][upper_row])
  'basic'
end

def sensitivity_lines(model, result)
  form, tableau = result.values_at(:form, :tableau)
  reduced = tableau.reduced(form[:phase2])
  nonbasic = form[:column_names].each_index.reject { |k| tableau.basic.include?(k) || form[:artificial][k] }
  dual = model[:constraints].each_index.map { |i| -form[:direction] * form[:signs][i] * reduced[form[:initial][i]] }
  variable_reduced = model[:costs].each_index.map do |j|
    model[:costs][j] - dot(dual, model[:matrix].map { |row| row[j] })
  end
  primal_degeneracy = tableau.basic.each_index.count { |i| !form[:artificial][tableau.basic[i]] && tableau.beta[i] == 0 }
  dual_degeneracy = nonbasic.count { |column| reduced[column] == 0 }
  dual_objective = dot(dual, model[:rhs]) + dot(variable_reduced, result[:solution])
  kind = model[:integer].any? ? 'relaxation' : 'lp'
  lines = ["MODEL #{model[:name]} #{kind} objective #{Q.f(result[:objective])}",
           'BASIS ' + tableau.basic.map { |column| form[:column_names][column] }.join(' '),
           "DEGENERACY primal #{primal_degeneracy} dual #{dual_degeneracy}", "DUAL objective #{Q.f(dual_objective)}"]
  model[:constraints].each_with_index do |constraint, i|
    lower, upper = rhs_range(model, result, i)
    lines << "CONSTRAINT #{constraint[:name]} price #{Q.f(dual[i])} rhs #{Q.f(model[:rhs][i])} range #{Q.endpoint(lower, true)} #{Q.endpoint(upper, false)}"
  end
  model[:variables].each_with_index do |name, j|
    lower, upper = objective_range(model, result, j, reduced, nonbasic)
    status = variable_status(form, tableau.basic, j)
    lines << "VARIABLE #{name} #{status} value #{Q.f(result[:solution][j])} reduced #{Q.f(variable_reduced[j])} cost #{Q.f(model[:costs][j])} range #{Q.endpoint(lower, true)} #{Q.endpoint(upper, false)}"
  end
  lines
end

def solve_model(model, level, limit)
  solve = ->(lower, upper, number) { solve_lp(model, lower, upper, number, level) }
  return BranchBound.search(model, limit, &solve) if model[:integer].any?
  result = solve.call(model[:lower], model[:upper], 1)
  {status: result[:status], objective: result[:objective],
   solution: result[:status] == 'OPTIMAL' ? result[:solution] : nil,
   solves: [result], root: result, nodes: 1, lines: []}
end

def solution_lines(model, result)
  root, integer_count = result[:root], model[:integer].count(true)
  lines = ["MODEL #{model[:name]} #{model[:direction]} variables #{model[:variables].length} constraints #{model[:constraints].length} integers #{integer_count}",
           statistics_line(model), "STATUS #{result[:status]}"]
  if result[:solution]
    lines << "OBJECTIVE #{Q.f(result[:objective])} approx #{Q.approx(result[:objective])}"
  end
  if integer_count > 0 && root[:status] == 'OPTIMAL'
    lines << "RELAXATION #{Q.f(root[:objective])} approx #{Q.approx(root[:objective])}"
  end
  if root[:status] == 'INFEASIBLE'
    lines << "INFEASIBILITY #{Q.f(root[:infeasibility])}"
    root[:form][:row_names].zip(farkas_multipliers(root)).each { |name, value| lines << "FARKAS #{name} #{Q.f(value)}" }
  end
  values = result[:status] == 'UNBOUNDED' ? root[:solution] : result[:solution]
  if values
    model[:variables].zip(values).each { |name, value| lines << "VALUE #{name} #{Q.f(value)}" }
  end
  if result[:status] == 'UNBOUNDED'
    ray, rate = unbounded_ray(model, root)
    model[:variables].zip(ray).each { |name, value| lines << "RAY #{name} #{Q.f(value)}" }
    lines << "RATE #{Q.f(rate)}"
  end
  if result[:solution]
    model[:constraints].each_with_index do |constraint, i|
      value = dot(model[:matrix][i], result[:solution])
      margin = model[:comparisons][i] == '<=' ? model[:rhs][i] - value : value - model[:rhs][i]
      lines << "ROW #{constraint[:name]} #{Q.f(value)} #{Q.f(margin)}"
    end
  end
  lines << "NODES #{result[:nodes]}" if integer_count > 0
  lines << "PIVOTS #{result[:solves].sum { |lp| lp[:pivots] }}"
  lines
end

def main
  settings = LPParser.read_settings
  reports = %w[iterations solutions sensitivity bnb_tree].to_h { |name| [name, []] }
  reports['summary'] = ['model,status,objective,approx,relaxation,nodes,pivots']
  statuses = %w[OPTIMAL INFEASIBLE UNBOUNDED NODE_LIMIT ERROR].to_h { |status| [status, 0] }
  total_solves = phase1 = phase2 = drives = analyzed = integer_models = integer_nodes = limited = 0
  models = LPParser.read_models
  models.each do |parsed|
    model = content_check(parsed)
    name = model[:name]
    if model[:error]
      line, message = model[:error]
      statuses['ERROR'] += 1
      reports['iterations'] << "MODEL #{name} error"
      reports['solutions'].concat(["MODEL #{name}", "STATUS ERROR line #{line} #{message}"])
      reports['sensitivity'] << "MODEL #{name} skipped ERROR"
      reports['summary'] << "#{name},ERROR,-,-,-,0,0"
      next
    end
    level = settings[:logs].fetch(name, settings[:level])
    limit = settings[:limits].fetch(name, settings[:limit])
    result = solve_model(model, level, limit)
    statuses[result[:status]] += 1
    reports['iterations'] << "MODEL #{name} level #{level}"
    result[:solves].each do |lp|
      reports['iterations'].concat(lp[:lines])
      total_solves += 1
      phase1 += lp[:phase1]
      phase2 += lp[:phase2]
      drives += lp[:drives]
    end
    reports['solutions'].concat(solution_lines(model, result))
    if result[:root][:status] == 'OPTIMAL'
      analyzed += 1
      reports['sensitivity'].concat(sensitivity_lines(model, result[:root]))
    else
      reports['sensitivity'] << "MODEL #{name} skipped #{result[:root][:status]}"
    end
    if model[:integer].any?
      integer_models += 1
      integer_nodes += result[:nodes]
      limited += 1 if result[:status] == 'NODE_LIMIT'
      reports['bnb_tree'] << "MODEL #{name} #{model[:direction]} integers #{model[:integer].count(true)} node_limit #{limit}"
      reports['bnb_tree'].concat(result[:lines])
    end
    approx = result[:objective] ? Q.approx(result[:objective]) : '-'
    pivots = result[:solves].sum { |lp| lp[:pivots] }
    reports['summary'] << [name, result[:status], Q.f(result[:objective]), approx,
                           Q.f(result[:root][:objective]), result[:solves].length, pivots].join(',')
  end
  reports['iterations'] << "TOTAL solves #{total_solves} phase1 #{phase1} phase2 #{phase2} drives #{drives} pivots #{phase1 + phase2 + drives}"
  reports['solutions'] << "SUMMARY models #{models.length} optimal #{statuses['OPTIMAL']} infeasible #{statuses['INFEASIBLE']} unbounded #{statuses['UNBOUNDED']} node_limit #{statuses['NODE_LIMIT']} error #{statuses['ERROR']}"
  reports['sensitivity'] << "SUMMARY analyzed #{analyzed} skipped #{models.length - analyzed}"
  reports['bnb_tree'] << "SUMMARY models #{integer_models} nodes #{integer_nodes} node_limit #{limited}"
  reports.each do |name, lines|
    extension = name == 'summary' ? 'csv' : 'txt'
    File.write("output/#{name}.#{extension}", lines.map { |line| line.rstrip + "\n" }.join)
  end
end

main if $PROGRAM_NAME == __FILE__
