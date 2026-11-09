require 'fileutils'
require_relative 'network_io'
require_relative 'learning'
require_relative 'factors'
require_relative 'elimination'
require_relative 'sampling'

class NetworkAnalysis
  def initialize(network, samples, params)
    @names, @states, @parents, @expert = network.names, network.states, network.parents, network.expert
    @samples, @params = samples, params
    @sizes = @states.map(&:length)
    @variables = (0...@names.length).to_a
    @children = @variables.map { |variable| @variables.select { |child| @parents[child].include?(variable) } }
    @topological, selected = [], []
    until selected.length == @variables.length
      variable = @variables.find { |item| !selected.include?(item) && (@parents[item] - selected).empty? }
      @topological << variable
      selected << variable
    end
    @depths = Array.new(@variables.length, 0)
    @topological.each { |variable| @depths[variable] = @parents[variable].map { |parent| @depths[parent] + 1 }.max || 0 }
    @ancestors = @variables.map { |variable| closure(@parents[variable], @parents) }
    @descendants = @variables.map { |variable| closure(@children[variable], @children) }
    @spouses = @variables.map do |variable|
      (@children[variable].flat_map { |child| @parents[child] }.uniq -
        @parents[variable] - @children[variable] - [variable]).sort
    end
    @blankets = @variables.map { |variable| (@parents[variable] | @children[variable] | @spouses[variable]).sort }
    @counts = @variables.map { |variable| Learning.count_samples(variable, @parents[variable], samples, @sizes) }
    @learned = @counts.map { |counts| Learning.learn(counts, params[:alpha]) }
    @cpts = @variables.map { |variable| params[:sources][variable] == 'GIVEN' ? @expert[variable] : @learned[variable] }
    @likelihoods = @counts.zip(@cpts).map { |counts, cpt| Learning.log_likelihood(counts, cpt) }
    @parameters = @counts.map { |counts| Learning.parameter_count(counts) }
    @factors = @variables.map { |variable| Factors.cpt_factor(variable, @parents[variable], @cpts[variable], @sizes) }
    @random = Sampling::Minstd.new(params[:seed])
    @family_scores = {}
  end

  def real(value)
    text = format('%.4f', value)
    text == '-0.0000' ? '0.0000' : text
  end

  def yes(value)
    value ? 'yes' : 'no'
  end

  def closure(initial, links)
    reached, pending = initial.to_a.uniq, initial.to_a.dup
    until pending.empty?
      links[pending.pop].each do |neighbor|
        next if reached.include?(neighbor)

        reached << neighbor
        pending << neighbor
      end
    end
    reached.sort
  end

  def sequence(variables)
    variables.empty? ? '-' : variables.map { |variable| @names[variable] }.join(' ')
  end

  def assignment_text(assignment, variables = assignment.keys.sort)
    return '-' if variables.empty?

    variables.map { |variable| "#{@names[variable]}=#{@states[variable][assignment[variable]]}" }.join(' ')
  end

  def evidence(fields)
    fields.to_h do |field|
      name, state = field.split('=')
      variable = @names.index(name)
      [variable, @states[variable].index(state)]
    end
  end

  def query_parts(fields)
    separator = fields.index('|')
    return [fields.map { |name| @names.index(name) }, {}] unless separator

    [fields.take(separator).map { |name| @names.index(name) }, evidence(fields.drop(separator + 1))]
  end

  def plans(initial, eliminate)
    %w[MINFILL GIVEN].to_h do |method|
      [method, Elimination.make_plan(initial, eliminate, method, @params[:order], @sizes)]
    end
  end

  def sum_result(initial, plan, query)
    factor, = Elimination.execute(initial, plan, @sizes)
    probability = Learning.total(factor.values)
    distribution = Factors::Factor.new(factor.variables, factor.values.map { |value| value / probability }, @sizes)
    marginals = query.to_h { |variable| [variable, Array.new(@sizes[variable], 0.0)] }
    Factors.assignments(distribution.variables, @sizes).zip(distribution.values).each do |assignment, value|
      query.each { |variable| marginals[variable][assignment[variable]] += value }
    end
    [distribution, probability, marginals]
  end

  def posterior(query, observed)
    relevant = closure(query | observed.keys, @parents)
    eliminate = relevant - query - observed.keys
    initial = relevant.map { |variable| @factors[variable].reduced(observed) }
    orders = plans(initial, eliminate)
    distribution, probability, marginals = sum_result(initial, orders[@params[:method]], query)
    { relevant: relevant, eliminate: eliminate, initial: initial, plans: orders,
      distribution: distribution, probability: probability, marginals: marginals }
  end

  def joint(assignment, variables)
    variables.inject(1.0) do |probability, variable|
      row = Learning.parent_row(@parents[variable], assignment, @sizes)
      probability * @cpts[variable][row][assignment[variable]]
    end
  end

  def query_enumeration(result, query, observed)
    free = result[:relevant] - observed.keys
    count = Factors.entry_count(free, @sizes)
    return [count, 'skipped'] if count > @params[:limit]

    query = query.sort
    values = Array.new(Factors.entry_count(query, @sizes), 0.0)
    Factors.assignments(free, @sizes).each do |assignment|
      assignment.merge!(observed)
      values[Learning.parent_row(query, assignment, @sizes)] += joint(assignment, result[:relevant])
    end
    probability = Learning.total(values)
    agreed = (Math.log(probability) - Math.log(result[:probability])).abs <= 1e-9
    agreed &&= values.zip(result[:distribution].values).all? { |value, target| (value / probability - target).abs <= 1e-9 }
    [count, agreed ? 'agree' : 'disagree']
  end

  def elimination_lines(result, agreement, enumeration)
    lines = ["relevant #{sequence(result[:relevant])}", "pruned #{sequence(@variables - result[:relevant])}",
             "eliminate #{sequence(result[:eliminate])}"]
    %w[MINFILL GIVEN].each do |method|
      plan = result[:plans][method]
      lines << "order #{method.downcase}"
      plan.steps.each do |step|
        lines << "step #{@names[step.variable]} fill #{step.fill} scope #{sequence(step.scope)} entries #{step.size}"
      end
      lines << "cost max #{plan.maximum} total #{plan.total}"
    end
    lines + ["used #{@params[:method].downcase}", "orders_agree #{yes(agreement)}", "enumeration #{enumeration.join(' ')}"]
  end

  def marginal_lines(prefix, query, marginals)
    query.map do |variable|
      values = @states[variable].zip(marginals[variable]).map { |state, value| "#{state} #{real(value)}" }
      "#{prefix} #{@names[variable]} #{values.join(' ')}"
    end
  end

  def answer_query(query, observed)
    result = posterior(query, observed)
    lines = ["log_evidence #{real(Math.log(result[:probability]))}"]
    unless observed.empty?
      conflict = Learning.total(observed.map { |variable, state| Math.log(posterior([], { variable => state })[:probability]) })
      lines << "conflict #{real(conflict - Math.log(result[:probability]))}"
    end
    if query.length >= 2
      distribution = result[:distribution]
      Factors.assignments(distribution.variables, @sizes).zip(distribution.values).each do |assignment, probability|
        lines << "joint #{assignment_text(assignment)} #{real(probability)}"
      end
    end
    lines.concat(marginal_lines('marginal', query, result[:marginals]))
    observed.each do |variable, state|
      without = posterior(query, observed.reject { |other, _| other == variable })[:marginals]
      shift = query.flat_map do |item|
        result[:marginals][item].zip(without[item]).map { |left, right| (left - right).abs }
      end.max
      lines << "drop #{@names[variable]}=#{@states[variable][state]} shift #{real(shift)}"
    end
    first, first_z, = sum_result(result[:initial], result[:plans]['MINFILL'], query)
    second, second_z, = sum_result(result[:initial], result[:plans]['GIVEN'], query)
    agreement = (Math.log(first_z) - Math.log(second_z)).abs <= 1e-9 &&
                first.values.zip(second.values).all? { |left, right| (left - right).abs <= 1e-9 }
    [lines, elimination_lines(result, agreement, query_enumeration(result, query, observed))]
  end

  def mpe_enumeration(eliminate, observed, assignment, maximum)
    count = Factors.entry_count(eliminate, @sizes)
    return [count, 'skipped'] if count > @params[:limit]

    best_probability, best_assignment = -1.0, nil
    Factors.assignments(eliminate, @sizes).each do |candidate|
      candidate.merge!(observed)
      probability = joint(candidate, @variables)
      next unless probability > best_probability

      best_probability, best_assignment = probability, candidate
    end
    agreement = best_assignment == assignment && (Math.log(best_probability) - Math.log(maximum)).abs <= 1e-9
    [count, agreement ? 'agree' : 'disagree']
  end

  def answer_mpe(observed)
    initial = @factors.map { |factor| factor.reduced(observed) }
    eliminate = @variables - observed.keys
    orders = plans(initial, eliminate)
    outcomes = orders.to_h do |method, plan|
      factor, products = Elimination.execute(initial, plan, @sizes, true)
      [method, [factor.values[0], Elimination.traceback(products, @sizes).merge(observed)]]
    end
    maximum, assignment = outcomes[@params[:method]]
    probability = observed.empty? ? 1.0 : posterior([], observed)[:probability]
    lines = ["assignment #{assignment_text(assignment)}", "log_joint #{real(Math.log(maximum))}",
             "log_evidence #{real(Math.log(probability))}", "posterior #{real(maximum / probability)}"]
    eliminate.each do |variable|
      plan = Elimination.make_plan(initial, eliminate - [variable], @params[:method], @params[:order], @sizes)
      factor, = Elimination.execute(initial, plan, @sizes, true)
      alternatives = (0...@sizes[variable]).to_a - [assignment[variable]]
      alternative = alternatives.max_by { |state| factor.values[state] }
      margin = Math.log(maximum) - Math.log(factor.values[alternative])
      lines << "margin #{@names[variable]} #{@states[variable][alternative]} #{real(margin)}"
    end
    first, second = outcomes.values_at('MINFILL', 'GIVEN')
    agreement = first[1] == second[1] && (Math.log(first[0]) - Math.log(second[0])).abs <= 1e-9
    result = { relevant: @variables, eliminate: eliminate, plans: orders }
    [lines, elimination_lines(result, agreement, mpe_enumeration(eliminate, observed, assignment, maximum))]
  end

  def answer_sample(number, query, observed, counts)
    exact = posterior(query, observed)[:marginals]
    lines, csv_lines = marginal_lines('exact', query, exact), []
    weight, squared_weight = 0.0, 0.0
    weights = query.to_h { |variable| [variable, Array.new(@sizes[variable], 0.0)] }
    (1..counts.last).each do |index|
      sample, current = Sampling.weighted_sample(@topological, @parents, @cpts, @sizes, observed, @random)
      weight += current
      squared_weight += current * current
      query.each { |variable| weights[variable][sample[variable]] += current }
      next unless counts.include?(index)

      maximum_error = 0.0
      query.each do |variable|
        weights[variable].each_with_index do |value, state|
          estimate, probability = value / weight, exact[variable][state]
          error = (estimate - probability).abs
          maximum_error = [maximum_error, error].max
          csv_lines << [number, index, @names[variable], @states[variable][state],
                        real(estimate), real(probability), real(error)].join(',')
        end
      end
      lines << "after #{index} weight #{real(weight)} ess #{real(weight * weight / squared_weight)} max_error #{real(maximum_error)}"
    end
    [lines, csv_lines]
  end

  def answer_predict(variable)
    size = @sizes[variable]
    confusion = Array.new(size) { Array.new(size, 0) }
    likelihood = 0.0
    @samples.each do |sample|
      assignment = sample.dup
      values = Array.new(size) do |state|
        assignment[variable] = state
        row = Learning.parent_row(@parents[variable], assignment, @sizes)
        probability = @cpts[variable][row][state]
        @children[variable].each do |child|
          row = Learning.parent_row(@parents[child], assignment, @sizes)
          probability *= @cpts[child][row][assignment[child]]
        end
        probability
      end
      denominator = Learning.total(values)
      probabilities = values.map { |value| value / denominator }
      predicted = (0...size).max_by { |state| probabilities[state] }
      actual = sample[variable]
      confusion[actual][predicted] += 1
      likelihood += Math.log(probabilities[actual])
    end
    correct = (0...size).inject(0) { |total, state| total + confusion[state][state] }
    count = @samples.length
    lines = ["blanket #{sequence(@blankets[variable])}", "accuracy #{correct}/#{count} #{real(correct.to_f / count)}",
             "log_loss #{real(-likelihood / count)}", "predicted #{@states[variable].join(' ')}"]
    lines + @states[variable].zip(confusion).map { |state, row| "actual #{state} #{row.join(' ')}" }
  end

  def reachable(x, z)
    ancestors = closure(z, @parents)
    pending = x.sort.map { |variable| [variable, :up] }
    visited = pending.to_set
    position = 0
    while position < pending.length
      variable, direction = pending[position]
      position += 1
      following = []
      if direction == :up && !z.include?(variable)
        following.concat(@parents[variable].map { |parent| [parent, :up] })
        following.concat(@children[variable].map { |child| [child, :down] })
      elsif direction == :down
        following.concat(@children[variable].map { |child| [child, :down] }) unless z.include?(variable)
        following.concat(@parents[variable].map { |parent| [parent, :up] }) if ancestors.include?(variable)
      end
      following.each { |item| pending << item if visited.add?(item) }
    end
    (visited.map(&:first).uniq - x - z).sort
  end

  def mutual_information(x, y, z)
    scope, xz, yz = (x | y | z).sort, (x | z).sort, (y | z).sort
    z = z.sort
    count_sets = [scope, xz, yz, z].map do |variables|
      counts = Hash.new(0)
      @samples.each { |sample| counts[variables.map { |variable| sample[variable] }] += 1 }
      counts
    end
    information, count = 0.0, @samples.length
    count_sets[0].keys.sort.each do |states|
      assignment = scope.zip(states).to_h
      observed = count_sets[0][states]
      n_xz = count_sets[1][xz.map { |variable| assignment[variable] }]
      n_yz = count_sets[2][yz.map { |variable| assignment[variable] }]
      n_z = count_sets[3][z.map { |variable| assignment[variable] }]
      argument = (observed * n_z).to_f / (n_xz * n_yz).to_f
      information += (observed.to_f / count) * Math.log(argument)
    end
    degrees = (Factors.entry_count(x, @sizes) - 1) * (Factors.entry_count(y, @sizes) - 1) * Factors.entry_count(z, @sizes)
    [information, 2 * count * information, degrees]
  end

  def answer_dsep(groups)
    x, y, z = groups[0], groups[1], groups[2] || []
    reached = reachable(x, z)
    information, statistic, degrees = mutual_information(x, y, z)
    ["result #{(reached & y).empty? ? 'separated' : 'connected'}", "reachable #{sequence(reached)}",
     "data cmi #{real(information)} g2 #{real(statistic)} df #{degrees}"]
  end

  def answer_blanket(variable)
    blanket = @blankets[variable]
    rest = @variables - blanket - [variable]
    ["parents #{sequence(@parents[variable])}", "children #{sequence(@children[variable])}",
     "spouses #{sequence(@spouses[variable])}", "blanket #{sequence(blanket)}", "rest #{sequence(rest)}",
     "rest_separated #{yes((reachable([variable], blanket) & rest).empty?)}"]
  end

  def path(start, finish, ignored = nil)
    previous, pending = { start => nil }, [start]
    position = 0
    while position < pending.length
      variable = pending[position]
      position += 1
      @children[variable].each do |child|
        next if [variable, child] == ignored || previous.key?(child)

        previous[child] = variable
        if child == finish
          result, current = [], child
          until current.nil?
            result << current
            current = previous[current]
          end
          return result.reverse
        end
        pending << child
      end
    end
    nil
  end

  def score(variable, parents)
    key = [variable, parents.sort]
    @family_scores[key] ||= Learning.family_score(variable, key[1], @samples, @sizes, @params[:alpha])
  end

  def answer_edge(operation, x, y)
    exists = @parents[y].include?(x)
    return ['result exists'] if operation == 'ADD' && exists
    return ['result missing'] if operation != 'ADD' && !exists

    cycle = nil
    if operation == 'ADD'
      found = path(y, x)
      cycle = [x] + found if found
    elsif operation == 'REVERSE'
      found = path(x, y, [x, y])
      cycle = [y] + found if found
    end
    return ["result cycle #{cycle.map { |variable| @names[variable] }.join(' -> ')}"] if cycle

    before_y = score(y, @parents[y])
    parents_y = operation == 'ADD' ? @parents[y] | [x] : @parents[y] - [x]
    after_y = score(y, parents_y)
    change = after_y - before_y
    lines = ['result ok', "family #{@names[y]} before #{real(before_y)} after #{real(after_y)}"]
    if operation == 'REVERSE'
      before_x, after_x = score(x, @parents[x]), score(x, @parents[x] | [y])
      change = (after_y - before_y) + (after_x - before_x)
      lines << "family #{@names[x]} before #{real(before_x)} after #{real(after_x)}"
    end
    lines << "delta #{real(change)} #{change.positive? ? 'improves' : 'worsens'}"
  end

  def cpt_blocks
    count = @samples.length
    blocks = @variables.map do |variable|
      source = @params[:sources][variable]
      parents, cpt, counts = @parents[variable], @cpts[variable], @counts[variable]
      lines = ["variable #{@names[variable]} source #{source}", "states #{@states[variable].join(' ')}", "parents #{sequence(parents)}"]
      Factors.assignments(parents, @sizes).each_with_index do |assignment, row|
        lines << "row #{assignment_text(assignment, parents)} counts #{counts[row].join(' ')} probs #{cpt[row].map { |value| real(value) }.join(' ')}"
      end
      likelihood, parameters = @likelihoods[variable], @parameters[variable]
      lines << "loglik #{real(likelihood)} parameters #{parameters} bic #{real(likelihood - parameters * Math.log(count) / 2)}"
      marginal = posterior([variable], {})[:marginals][variable]
      frequencies = Array.new(@sizes[variable]) { |state| counts.inject(0) { |total, row| total + row[state] }.to_f / count }
      lines << "marginal model #{marginal.map { |value| real(value) }.join(' ')} data #{frequencies.map { |value| real(value) }.join(' ')}"
      if source == 'LEARNED'
        difference = '-'
        if @expert.key?(variable)
          difference = real(@learned[variable].zip(@expert[variable]).flat_map do |learned, given|
            learned.zip(given).map { |left, right| (left - right).abs }
          end.max)
        end
        lines << "given_difference #{difference}"
      end
      lines
    end
    likelihood = Learning.total(@likelihoods)
    parameters = @parameters.inject(0, :+)
    blocks << ["network samples #{count} pseudocount #{real(@params[:alpha])} loglik #{real(likelihood)} parameters #{parameters} bic #{real(likelihood - parameters * Math.log(count) / 2)}"]
  end

  def structure_summary
    orders = plans(@factors, @variables)
    widths = orders.transform_values { |plan| plan.steps.map { |step| step.scope.length }.max - 1 }
    moral_edges = Elimination.interaction_graph(@factors).values.inject(0) { |total, neighbors| total + neighbors.length } / 2
    edges = @parents.inject(0) { |total, parents| total + parents.length }
    lines = ["variables #{@variables.length} edges #{edges}", "topological_order #{sequence(@topological)}",
             "roots #{sequence(@variables.select { |variable| @parents[variable].empty? })}",
             "leaves #{sequence(@variables.select { |variable| @children[variable].empty? })}",
             "moral_edges #{moral_edges} width minfill #{widths['MINFILL']} given #{widths['GIVEN']}"]
    @variables.each do |variable|
      lines << "variable #{@names[variable]} states #{@sizes[variable]} parents #{@parents[variable].length} children #{@children[variable].length} depth #{@depths[variable]} ancestors #{@ancestors[variable].length} descendants #{@descendants[variable].length} blanket #{@blankets[variable].length}"
    end
    lines
  end

  def process_queries(queries)
    answers, elimination, structure = [], [], [structure_summary]
    sampling = ['query,samples,variable,state,estimate,exact,abs_error']
    queries.each_with_index do |line, index|
      kind, *fields = line.split
      number = index + 1
      heading = "query #{number} #{line}"
      case kind
      when 'QUERY'
        answer, steps = answer_query(*query_parts(fields))
        answers << [heading] + answer
        elimination << [heading] + steps
      when 'MPE'
        answer, steps = answer_mpe(evidence(fields))
        answers << [heading] + answer
        elimination << [heading] + steps
      when 'SAMPLE'
        separator = fields.index('COUNTS')
        query, observed = query_parts(fields.take(separator))
        answer, rows = answer_sample(number, query, observed, fields.drop(separator + 1).map(&:to_i))
        answers << [heading] + answer
        sampling.concat(rows)
      when 'PREDICT'
        answers << [heading] + answer_predict(@names.index(fields[0]))
      when 'DSEP'
        groups = [[]]
        fields.each { |field| field == '|' ? groups << [] : groups.last << @names.index(field) }
        structure << [heading] + answer_dsep(groups)
      when 'BLANKET'
        structure << [heading] + answer_blanket(@names.index(fields[0]))
      when 'EDGE'
        operation, x, y = fields
        structure << [heading] + answer_edge(operation, @names.index(x), @names.index(y))
      end
    end
    [answers, elimination, structure, sampling]
  end
end

def write_blocks(path, blocks)
  text = blocks.map { |block| block.join("\n") }.join("\n\n")
  File.write(path, text.empty? ? '' : text + "\n")
end

if $PROGRAM_NAME == __FILE__
  network, samples, queries, params = NetworkIO.read_inputs
  analysis = NetworkAnalysis.new(network, samples, params)
  cpts = analysis.cpt_blocks
  answers, elimination, structure, sampling = analysis.process_queries(queries)
  FileUtils.mkdir_p('output')
  write_blocks('output/cpts.txt', cpts)
  write_blocks('output/structure.txt', structure)
  write_blocks('output/answers.txt', answers)
  write_blocks('output/elimination.txt', elimination)
  write_blocks('output/sampling.csv', [sampling])
end
