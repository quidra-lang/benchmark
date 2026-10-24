require_relative 'pddl_parser'

module Strips
  Action = Struct.new(:number, :source, :arguments, :cost, :pre, :neg, :add, :delete)
  Grounded = Struct.new(:name, :source, :objects_by_type, :statistics, :candidate_count, :facts,
                        :actions, :initial, :goal, :unreachable, :static_count, :action_numbers,
                        :evaluator, :results, :proof, :best, :optimal)

  def self.subtype?(parents, actual, expected)
    until actual.nil?
      return true if actual == expected
      actual = parents[actual]
    end
    false
  end
  def self.predicate_classes(domain)
    domain.fluent = domain.actions.flat_map { |action| action.effects.map { |_, atom| atom.predicate } }.to_set
    domain.static = domain.predicates.keys.to_set - domain.fluent
  end
  def self.substitute(atom, assignment) = Atom.new(atom.predicate, atom.terms.map { |term| assignment.fetch(term) })

  # Fact sets and states are immutable integer bitsets.
  def self.members(mask)
    values = []
    until mask.zero?
      bit = mask & -mask
      values << bit.bit_length - 1
      mask ^= bit
    end
    values
  end
  def self.mask(numbers) = numbers.reduce(0) { |result, number| result | (1 << number) }
  def self.subset?(first, second) = (first & second) == first
  def self.cardinality(bits) = members(bits).length

  def self.ground(domain, problem)
    objects_by_type = domain.type_order.to_h do |type|
      [type, problem.objects.filter_map { |name, actual| name if subtype?(domain.parents, actual, type) }]
    end
    initial_atoms = problem.initial.to_set
    candidates, statistics = [], {}
    domain.actions.each do |schema|
      choices = schema.parameters.map { |_, type| objects_by_type[type] }
      statistics[schema.name] = [choices.reduce(1) { |total, choice| total * choice.length }, 0, 0]
      combinations = [[]]
      choices.each { |choice| combinations = combinations.flat_map { |prefix| choice.map { |value| prefix + [value] } } }
      combinations.each do |arguments|
        binding = schema.parameters.map(&:first).zip(arguments).to_h
        positive, negative, accepted = Set.new, Set.new, true
        schema.condition.each do |sign, atom|
          bound = substitute(atom, binding)
          if bound.predicate == '='
            truth = bound.terms[0] == bound.terms[1]
          elsif domain.static.include?(bound.predicate)
            truth = initial_atoms.include?(bound)
          else
            (sign ? positive : negative) << bound
            next
          end
          if truth != sign
            accepted = false
            break
          end
        end
        next unless accepted
        adds = schema.effects.filter_map { |sign, atom| substitute(atom, binding) if sign }.to_set
        deletes = schema.effects.filter_map { |sign, atom| substitute(atom, binding) unless sign }.to_set - adds
        candidates << Action.new(nil, schema, arguments, schema.cost, positive, negative, adds, deletes)
        statistics[schema.name][1] += 1
      end
    end
    reachable = problem.initial.select { |atom| domain.fluent.include?(atom.predicate) }.to_set
    accepted = Set.new
    loop do
      changed = false
      candidates.each_with_index do |candidate, number|
        next if accepted.include?(number) || !candidate.pre.subset?(reachable)
        accepted << number
        reachable.merge(candidate.add)
        statistics[candidate.source.name][2] += 1
        changed = true
      end
      break unless changed
    end
    predicate_order = domain.predicates.keys.each_with_index.to_h
    object_order = problem.objects.keys.each_with_index.to_h
    facts = reachable.sort_by { |atom| [predicate_order[atom.predicate], atom.terms.map { |name| object_order[name] }] }
    fact_numbers = facts.each_with_index.to_h
    actions = []
    candidates.each_with_index do |candidate, number|
      next unless accepted.include?(number)
      mapped = [candidate.pre, candidate.neg, candidate.add, candidate.delete].map do |values|
        mask(values.filter_map { |atom| fact_numbers[atom] })
      end
      actions << Action.new(actions.length, candidate.source, candidate.arguments, candidate.cost, *mapped)
    end
    initial = mask(problem.initial.filter_map { |atom| fact_numbers[atom] if domain.fluent.include?(atom.predicate) })
    goal, unreachable = 0, []
    problem.goals.each do |atom|
      if fact_numbers.key?(atom)
        goal |= 1 << fact_numbers[atom]
      elsif !domain.static.include?(atom.predicate) || !initial_atoms.include?(atom)
        unreachable << atom
      end
    end
    Grounded.new(problem.name, problem, objects_by_type, statistics, candidates.length, facts,
                 actions, initial, goal, unreachable, problem.initial.count { |atom| domain.static.include?(atom.predicate) },
                 actions.to_h { |action| [[action.source.name, action.arguments], action.number] })
  end
end
