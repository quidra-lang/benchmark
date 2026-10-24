require 'fileutils'
require_relative 'pddl_parser'
require_relative 'grounding'
require_relative 'heuristics'
require_relative 'search'
require_relative 'graphplan'

module Strips
  Validation = Struct.new(:status, :messages, :correct)
  Candidate = Struct.new(:number, :problem, :label, :steps)
  def self.notation(value)
    name, terms = value.is_a?(Atom) ? [value.predicate, value.terms] : value
    '(' + ([name] + terms).join(' ') + ')'
  end
  def self.action_text(action) = notation([action.source.name, action.arguments])
  def self.number_list(bits) = bits.zero? ? '-' : members(bits).join(',')
  def self.headed(heading, items) = heading + ' ' + (items.empty? ? '-' : items.join(' '))
  def self.value_text(value) = value.nil? ? 'inf' : value.to_s
  def self.heuristic_text(values) = HEURISTIC_NAMES.map { |name| "#{name}=#{value_text(values[name])}" }.join(' ')
  def self.plan_cost(problem, plan) = plan.sum { |number| problem.actions[number].cost }
  def self.plan_steps(problem, plan) = plan.map { |number| action = problem.actions[number]; [action.source.name, action.arguments] }

  def self.read_settings(text)
    settings = {'runs' => []}
    text.each_line(chomp: true) do |line|
      next if line.empty? || line.start_with?('#')
      kind, *fields = line.split(' ')
      if kind == 'run'
        settings['runs'] << fields
      elsif kind == 'repair'
        settings[kind] = fields
      else
        settings[kind] = fields.first.to_i
      end
    end
    settings
  end

  def self.read_candidates(text)
    candidates, current = [], nil
    text.each_line(chomp: true) do |line|
      next if line.empty? || line.start_with?('#')
      if line.start_with?('plan ')
        _, problem, label = line.split(' ')
        current = Candidate.new(candidates.length + 1, problem, label, [])
      elsif line == 'end'
        candidates << current
        current = nil
      else
        name, *arguments = line[1...-1].split(' ')
        current.steps << [name, arguments]
      end
    end
    candidates
  end

  def self.argument_error(domain, arguments, expected, table, noun)
    return "expected #{expected.length} arguments, got #{arguments.length}" unless arguments.length == expected.length
    arguments.zip(expected).each_with_index do |(argument, type), index|
      return "unknown #{noun} #{argument}" unless table.key?(argument)
      return "argument #{index + 1} (#{argument}) is not of type #{type}" unless subtype?(domain.parents, table[argument], type)
    end
    nil
  end

  def self.validate_domain(domain)
    diagnostics = []
    domain.actions = domain.actions.select do |action|
      unknown = action.parameters.find { |_, type| !domain.parents.key?(type) }
      error = unknown ? "unknown type #{unknown[1]}" : nil
      unless error
        table = action.parameters.to_h
        (action.condition + action.effects).each do |_, atom|
          if atom.predicate != '=' && !domain.predicates.key?(atom.predicate)
            error = "unknown predicate #{atom.predicate}"
          else
            expected = atom.predicate == '=' ? %w[object object] : domain.predicates[atom.predicate]
            error = argument_error(domain, atom.terms, expected, table, 'variable')
          end
          if error
            error = notation(atom) + ': ' + error
            break
          end
        end
      end
      diagnostics << "error: action #{action.name}: #{error}" if error
      error.nil?
    end
    used = domain.actions.flat_map { |action| (action.condition + action.effects).map { |_, atom| atom.predicate } }.to_set
    domain.predicates.each_key { |predicate| diagnostics << "warning: predicate #{predicate} is not used by any action" unless used.include?(predicate) }
    predicate_classes(domain)
    domain.diagnostics = diagnostics
  end

  def self.validate_problem(domain, problem)
    [['init', :initial], ['goal', :goals]].each do |side, attribute|
      seen = Set.new
      kept = problem.public_send(attribute).select do |atom|
        error = if domain.predicates.key?(atom.predicate)
                  argument_error(domain, atom.terms, domain.predicates[atom.predicate], problem.objects, 'object')
                else
                  "unknown predicate #{atom.predicate}"
                end
        error = 'duplicate' if error.nil? && seen.include?(atom)
        if error
          problem.diagnostics << "warning: #{side} #{notation(atom)}: #{error}"
          false
        else
          seen << atom
          true
        end
      end
      problem.public_send("#{attribute}=", kept)
    end
  end

  def self.validate_steps(domain, problem, steps)
    world, cost = problem.initial.to_set, 0
    by_name = domain.actions.to_h { |action| [action.name, action] }
    steps.each_with_index do |(name, arguments), index|
      heading = "step #{index + 1} #{notation([name, arguments])}: "
      schema = by_name[name]
      return Validation.new('invalid', [heading + "unknown action #{name}"], index) unless schema
      error = argument_error(domain, arguments, schema.parameters.map(&:last), problem.objects, 'object')
      return Validation.new('invalid', [heading + error], index) if error
      assignment = schema.parameters.map(&:first).zip(arguments).to_h
      schema.condition.each do |sign, atom|
        bound = substitute(atom, assignment)
        truth = bound.predicate == '=' ? bound.terms[0] == bound.terms[1] : world.include?(bound)
        next if truth == sign
        text = sign ? notation(bound) : '(not ' + notation(bound) + ')'
        return Validation.new('invalid', [heading + 'precondition ' + text + ' is false'], index)
      end
      deletes = schema.effects.filter_map { |sign, atom| substitute(atom, assignment) unless sign }.to_set
      adds = schema.effects.filter_map { |sign, atom| substitute(atom, assignment) if sign }.to_set
      world.subtract(deletes).merge(adds)
      cost += schema.cost
    end
    missing = problem.goals.filter_map { |atom| 'unsatisfied goal ' + notation(atom) unless world.include?(atom) }
    missing.empty? ? Validation.new('valid', ["length=#{steps.length} cost=#{cost}"], steps.length) : Validation.new('goal not reached', missing, steps.length)
  end
  def self.verdict(validation) = validation.status + (validation.status == 'valid' ? ' ' : ': ') + validation.messages.first

  def self.interferes?(first, second)
    !(first.delete & (second.pre | second.add)).zero? || !(second.delete & (first.pre | first.add)).zero? ||
      !(first.add & second.neg).zero? || !(second.add & first.neg).zero?
  end
  def self.parallelize(problem, plan)
    assigned, layers = [], []
    plan.each_with_index do |number, position|
      action, layer = problem.actions[number], 1
      position.times do |earlier|
        previous = problem.actions[plan[earlier]]
        if !(previous.add & action.pre).zero? || !(previous.delete & action.neg).zero? || interferes?(previous, action)
          layer = [layer, assigned[earlier] + 1].max
        end
      end
      assigned << layer
      layers << [] while layers.length < layer
      layers[layer - 1] << number
    end
    layers
  end
  def self.validate_parallel(problem, layers)
    state = problem.initial
    layers.each_with_index do |layer, index|
      actions = layer.map { |number| problem.actions[number] }
      if actions.any? { |action| !applicable?(action, state) } || actions.combination(2).any? { |first, second| interferes?(first, second) }
        return "invalid at layer #{index + 1}"
      end
      deletes = actions.reduce(0) { |facts, action| facts | action.delete }
      adds = actions.reduce(0) { |facts, action| facts | action.add }
      state = (state & ~deletes) | adds
    end
    subset?(problem.goal, state) ? 'valid' : 'goal not reached'
  end
  def self.improve(problem, plan)
    sequence, position = plan.dup, 0
    while position < sequence.length
      state = sequence.first(position).reduce(problem.initial) { |current, number| apply(problem.actions[number], current) }
      applied = []
      sequence.drop(position + 1).each do |number|
        action = problem.actions[number]
        next unless applicable?(action, state)
        state = apply(action, state)
        applied << number
      end
      if subset?(problem.goal, state)
        sequence = sequence.first(position) + applied
      else
        position += 1
      end
    end
    sequence
  end
  def self.reached_landmarks(problem, plan, landmarks)
    state, reached = problem.initial, 0
    plan.each do |number|
      state = apply(problem.actions[number], state)
      reached |= state & landmarks
    end
    reached
  end

  def self.transform_negatives(problem)
    negative = problem.actions.reduce(0) { |facts, action| facts | action.neg }
    complements = members(negative).each_with_index.to_h { |fact, index| [fact, problem.facts.length + index] }
    complement_mask = lambda { |facts| mask(members(facts).filter_map { |fact| complements[fact] }) }
    actions = problem.actions.map do |action|
      GraphElement.new(action.number, action.pre | complement_mask.call(action.neg),
                       action.add | complement_mask.call(action.delete), action.delete | complement_mask.call(action.add))
    end
    [actions, problem.initial | complement_mask.call(negative & ~problem.initial), complements.length]
  end

  class Planner
    def initialize
      @domain = Strips.read_domain(File.read('input/domain.txt'))
      @sources = Strips.read_problems(File.read('input/problems.txt'))
      @settings = Strips.read_settings(File.read('input/params.txt'))
      @candidates = Strips.read_candidates(File.read('input/candidates.txt'))
      Strips.validate_domain(@domain)
      @tags = @settings['runs'].map { |pair| pair.join(' ') } + ['graphplan']
      @totals = @tags.map { Hash.new(0) }
      @grounding_lines, @plan_lines, @graph_lines, @validation_lines = [], [], [], []
      @comparison_lines = ['problem,algorithm,heuristic,length,cost,expanded,generated']
      @problems = {}
      @validated_plans = @valid_plans = @valid_candidates = 0
    end

    def domain_report
      lines = @grounding_lines
      lines << "== domain #{@domain.name} =="
      lines.concat(@domain.diagnostics)
      @domain.type_order.each do |type|
        chain, current = [], type
        until current.nil?
          chain << current
          current = @domain.parents[current]
        end
        lines << 'type ' + chain.join(' < ')
      end
      @domain.predicates.each do |predicate, arguments|
        lines << "predicate #{predicate}/#{arguments.length} #{@domain.fluent.include?(predicate) ? 'fluent' : 'static'}"
      end
      @domain.actions.each do |action|
        adds = action.effects.count { |sign, _| sign }
        lines << "action #{action.name}/#{action.parameters.length} cost=#{action.cost} pre=#{action.condition.length} add=#{adds} del=#{action.effects.length - adds}"
      end
    end

    def grounding_report(problem)
      lines = @grounding_lines
      lines.concat(['', "== problem #{problem.name} =="] + problem.source.diagnostics)
      lines << "objects: #{problem.source.objects.length}"
      @domain.type_order.each { |type| lines << Strips.headed("  #{type}:", problem.objects_by_type[type]) }
      lines << "static facts: #{problem.static_count}"
      @domain.actions.each do |action|
        assignments, candidates, reachable = problem.statistics[action.name]
        lines << "schema #{action.name}: assignments=#{assignments} candidates=#{candidates} reachable=#{reachable}"
      end
      lines << "candidates: #{problem.candidate_count} reachable: #{problem.actions.length}"
      lines << "facts: #{problem.facts.length} init: #{Strips.cardinality(problem.initial)} goals: #{Strips.cardinality(problem.goal)}"
      problem.unreachable.each { |atom| lines << 'unreachable goal: ' + Strips.notation(atom) }
      counts = problem.facts.map(&:predicate).tally
      lines << Strips.headed('facts by predicate:', @domain.predicates.keys.filter_map { |name| "#{name}=#{counts.fetch(name, 0)}" if @domain.fluent.include?(name) })
      lines << 'facts:'
      problem.facts.each_with_index { |atom, number| lines << "  #{number} #{Strips.notation(atom)}" }
      lines << 'actions:'
      problem.actions.each do |action|
        lines << "  #{action.number} #{Strips.action_text(action)} cost=#{action.cost} pre=#{Strips.number_list(action.pre)} neg=#{Strips.number_list(action.neg)} add=#{Strips.number_list(action.add)} del=#{Strips.number_list(action.delete)}"
      end
    end

    def initial_report(problem)
      evaluator, lines = problem.evaluator, @plan_lines
      values = evaluator.values(problem.initial)
      landmarks = evaluator.landmarks(problem.initial) || 0
      relaxed = evaluator.relaxed_plan(problem.initial) || []
      lines << 'initial h: ' + Strips.heuristic_text(values)
      lines << "landmarks: #{Strips.cardinality(landmarks)}"
      Strips.members(landmarks).each { |number| lines << '  ' + Strips.notation(problem.facts[number]) }
      lines << "relaxed plan: length=#{relaxed.length} cost=#{Strips.value_text(values['ff'])}"
      relaxed.each { |number| lines << '  ' + Strips.action_text(problem.actions[number]) }
      lines << Strips.headed('helpful:', evaluator.helpful(problem.initial).map { |number| Strips.action_text(problem.actions[number]) })
      landmarks
    end

    def plan_report(problem, tag, plan, landmarks, earlier)
      lines = @plan_lines
      first = earlier[plan] ||= tag
      suffix = first == tag ? '' : " (same as #{first})"
      lines << "plan: length=#{plan.length} cost=#{Strips.plan_cost(problem, plan)}#{suffix}"
      plan.each_with_index { |number, index| lines << "  #{index + 1} #{Strips.action_text(problem.actions[number])}" }
      counts = plan.map { |number| problem.actions[number].source.name }.tally
      lines << Strips.headed('schemas:', @domain.actions.filter_map { |action| "#{action.name}=#{counts[action.name]}" if counts.key?(action.name) })
      layers = Strips.parallelize(problem, plan)
      lines << "parallel: layers=#{layers.length}"
      layers.each_with_index { |layer, index| lines << Strips.headed("  #{index + 1}:", layer.map { |number| Strips.action_text(problem.actions[number]) }) }
      improved = Strips.improve(problem, plan)
      removed = plan.length - improved.length
      lines << "improved: length=#{improved.length} cost=#{Strips.plan_cost(problem, improved)} removed=#{removed}"
      improved.each_with_index { |number, index| lines << "  #{index + 1} #{Strips.action_text(problem.actions[number])}" } if removed.positive?
      reached = Strips.reached_landmarks(problem, plan, landmarks)
      lines << "landmarks reached: #{Strips.cardinality(reached)}/#{Strips.cardinality(landmarks)}"
      Strips.members(landmarks & ~reached).each { |number| lines << '  missed ' + Strips.notation(problem.facts[number]) }
      checked = Strips.validate_steps(@domain, problem.source, Strips.plan_steps(problem, plan))
      checked_improved = Strips.validate_steps(@domain, problem.source, Strips.plan_steps(problem, improved))
      @validation_lines.concat([tag + ': ' + Strips.verdict(checked), '  parallel: ' + Strips.validate_parallel(problem, layers),
                                '  improved: ' + Strips.verdict(checked_improved)])
      @validated_plans += 1
      @valid_plans += 1 if checked.status == 'valid'
    end

    def search_result_report(problem, tag, outcome, landmarks, earlier)
      @plan_lines << "-- #{tag} --"
      unless problem.unreachable.empty?
        @plan_lines << 'result: FAIL (unreachable goal)'
        return
      end
      state = outcome.status == 'solved' ? 'solved' : "FAIL (#{outcome.status})"
      @plan_lines << "result: #{state} expanded=#{outcome.expanded} generated=#{outcome.generated}"
      plan_report(problem, tag, outcome.plan, landmarks, earlier) if outcome.status == 'solved'
    end

    def graph_report(problem, outcome, complements)
      lines = @graph_lines
      unless problem.unreachable.empty?
        lines << 'result: FAIL (unreachable goal)'
        return
      end
      lines << "complementary facts: #{complements}"
      lines.concat(outcome.lines)
      counts = " searched=#{outcome.expanded} memo_hits=#{outcome.memo_hits} tried=#{outcome.generated}"
      if outcome.status == 'solved'
        lines << "result: solved levels=#{outcome.layers.length} length=#{outcome.plan.length} cost=#{Strips.plan_cost(problem, outcome.plan)}#{counts}"
        outcome.layers.each_with_index { |layer, index| lines << Strips.headed("layer #{index + 1}:", layer.map { |number| Strips.action_text(problem.actions[number]) }) }
      else
        lines << "result: FAIL (#{outcome.status})#{counts}"
      end
    end

    def profile_report(problem)
      tag, outcome = @tags[problem.proof], problem.results[problem.proof]
      plan, state = outcome.plan, problem.initial
      remaining, overestimates = Strips.plan_cost(problem, plan), Hash.new(0)
      @plan_lines << "-- profile (#{tag}) --"
      (0..plan.length).each do |position|
        values = problem.evaluator.values(state)
        @plan_lines << "  #{position}: h*=#{remaining} #{Strips.heuristic_text(values)}"
        values.each { |name, value| overestimates[name] += 1 if value.nil? || value > remaining }
        next if position == plan.length
        action = problem.actions[plan[position]]
        state = Strips.apply(action, state)
        remaining -= action.cost
      end
      @plan_lines << 'overestimates: ' + HEURISTIC_NAMES.map { |name| "#{name}=#{overestimates[name]}" }.join(' ')
      @plan_lines << "-- causal links (#{tag}) --"
      suppliers = Hash.new(0)
      plan.each_with_index do |number, index|
        action = problem.actions[number]
        links = Strips.members(action.pre).map { |fact| "#{Strips.notation(problem.facts[fact])}<-#{suppliers[fact]}" }
        @plan_lines << Strips.headed("  #{index + 1} #{Strips.action_text(action)}:", links)
        Strips.members(action.add).each { |fact| suppliers[fact] = index + 1 }
      end
      @plan_lines << Strips.headed('  goal:', Strips.members(problem.goal).map { |fact| "#{Strips.notation(problem.facts[fact])}<-#{suppliers[fact]}" })
    end

    def summarize_problem(problem)
      solved = problem.results.select { |outcome| outcome.status == 'solved' }
      problem.best = solved.map { |outcome| Strips.plan_cost(problem, outcome.plan) }.min
      problem.optimal = if !problem.proof.nil?
                          Strips.plan_cost(problem, problem.results[problem.proof].plan).to_s
                        elsif problem.results.any? { |outcome| ['unreachable goal', 'dead end', 'exhausted', 'unreachable'].include?(outcome.status) }
                          'none'
                        else
                          'unknown'
                        end
      pairs = @settings['runs'] + [['graphplan', 'none']]
      problem.results.zip(pairs).each_with_index do |(outcome, (algorithm, heuristic)), index|
        totals = @totals[index]
        totals[:expanded] += outcome.expanded
        totals[:generated] += outcome.generated
        length = cost = '-'
        if outcome.status == 'solved'
          length, cost = outcome.plan.length, Strips.plan_cost(problem, outcome.plan)
          totals[:solved] += 1
          totals[:best] += 1 if cost == problem.best
        end
        @comparison_lines << [problem.name, algorithm, heuristic, length, cost, outcome.expanded, outcome.generated].join(',')
      end
    end

    def solve_problem(source)
      Strips.validate_problem(@domain, source)
      problem = Strips.ground(@domain, source)
      @problems[problem.name] = problem
      grounding_report(problem)
      [@plan_lines, @graph_lines, @validation_lines].each { |lines| lines << "== problem #{problem.name} ==" }
      problem.results, earlier, landmarks = [], {}, 0
      if problem.unreachable.empty?
        problem.evaluator = Heuristics.new(problem)
        landmarks = initial_report(problem)
      else
        @plan_lines << 'initial h: unreachable goal'
      end
      @settings['runs'].each_with_index do |(algorithm, heuristic), index|
        outcome = problem.unreachable.empty? ? Strips.run(problem, problem.initial, algorithm, heuristic, @settings['budget'], @settings['weight'], problem.evaluator) : Strips.result('unreachable goal')
        problem.results << outcome
        search_result_report(problem, @tags[index], outcome, landmarks, earlier)
        if problem.proof.nil? && [['ucs', 'none'], ['astar', 'hmax']].include?([algorithm, heuristic]) && outcome.status == 'solved'
          problem.proof = index
        end
      end
      complements = 0
      if problem.unreachable.empty?
        actions, initial, complements = Strips.transform_negatives(problem)
        graph = PlanningGraph.new(actions, initial, problem.goal, @settings['graphplan']).run
      else
        graph = Strips.result('unreachable goal')
      end
      problem.results << graph
      search_result_report(problem, 'graphplan', graph, landmarks, earlier)
      graph_report(problem, graph, complements)
      profile_report(problem) unless problem.proof.nil?
      summarize_problem(problem)
      [@plan_lines, @graph_lines, @validation_lines].each { |lines| lines << '' }
    end

    def summary_report
      @plan_lines << '== summary =='
      @problems.each_value do |problem|
        solved = problem.results.count { |outcome| outcome.status == 'solved' }
        @plan_lines << "#{problem.name}: solved=#{solved}/#{@tags.length} best=#{problem.best.nil? ? '-' : problem.best} optimal=#{problem.optimal}"
      end
      @tags.zip(@totals).each do |tag, totals|
        @plan_lines << "#{tag}: solved=#{totals[:solved]} best=#{totals[:best]} expanded=#{totals[:expanded]} generated=#{totals[:generated]}"
      end
    end

    def mapped_steps(problem, steps) = steps.map { |step| problem.action_numbers.fetch(step) }
    def repair_candidate(problem, candidate, checked)
      unless problem.unreachable.empty?
        @validation_lines << '  repair: FAIL (unreachable goal)'
        return
      end
      prefix = mapped_steps(problem, candidate.steps.first(checked.correct))
      state = prefix.reduce(problem.initial) { |current, number| Strips.apply(problem.actions[number], current) }
      algorithm, heuristic = @settings['repair']
      outcome = Strips.run(problem, state, algorithm, heuristic, @settings['budget'], @settings['weight'], problem.evaluator)
      unless outcome.status == 'solved'
        @validation_lines << "  repair: FAIL (#{outcome.status})"
        return
      end
      repaired = prefix + outcome.plan
      validation = Strips.validate_steps(@domain, problem.source, Strips.plan_steps(problem, repaired))
      @validation_lines << "  repair: kept=#{prefix.length} added=#{outcome.plan.length} #{Strips.verdict(validation)}"
      repaired.each_with_index { |number, index| @validation_lines << "    #{index + 1} #{Strips.action_text(problem.actions[number])}" }
    end

    def candidate_report
      lines = @validation_lines
      lines << '== candidates =='
      @candidates.each do |candidate|
        problem = @problems.fetch(candidate.problem)
        checked = Strips.validate_steps(@domain, problem.source, candidate.steps)
        heading = "candidate #{candidate.number} #{candidate.problem} #{candidate.label}: "
        if checked.status == 'valid'
          @valid_candidates += 1
          lines << heading + Strips.verdict(checked)
          mapped = mapped_steps(problem, candidate.steps)
          improved = Strips.improve(problem, mapped)
          lines << "  improved: length=#{improved.length} cost=#{Strips.plan_cost(problem, improved)} removed=#{mapped.length - improved.length} best known=#{problem.best.nil? ? '-' : problem.best}"
        else
          lines << heading + checked.status
          checked.messages.each { |message| lines << '  ' + message }
          repair_candidate(problem, candidate, checked)
        end
      end
      lines.concat(['', '== summary ==', "plans: #{@validated_plans} valid: #{@valid_plans}", "candidates: #{@candidates.length} valid: #{@valid_candidates}"])
    end

    def run
      domain_report
      @sources.each { |source| solve_problem(source) }
      summary_report
      candidate_report
      FileUtils.mkdir_p('output')
      {'grounding.txt' => @grounding_lines, 'plans.txt' => @plan_lines, 'graphplan.txt' => @graph_lines,
       'validation.txt' => @validation_lines, 'comparison.csv' => @comparison_lines}.each do |name, lines|
        File.write(File.join('output', name), lines.join("\n") + "\n", mode: 'wb')
      end
    end
  end
end

Strips::Planner.new.run if $PROGRAM_NAME == __FILE__
