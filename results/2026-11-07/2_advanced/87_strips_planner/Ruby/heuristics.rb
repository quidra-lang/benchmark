require_relative 'search'

module Strips
  HEURISTIC_NAMES = %w[goalcount hmax hadd ff lmcount].freeze
  class Heuristics
    def initialize(problem)
      @actions, @goal, @fact_count = problem.actions, problem.goal, problem.facts.length
      @achievers = Array.new(@fact_count) { [] }
      @actions.each { |action| Strips.members(action.add).each { |fact| @achievers[fact] << action.number } }
      @cost_cache, @plan_cache, @level_cache, @landmark_cache, @value_cache = {}, {}, {}, {}, {}
    end

    def relaxed_costs(state, maximum)
      key = [state, maximum]
      return @cost_cache[key] if @cost_cache.key?(key)
      costs = Array.new(@fact_count) { |fact| (state & (1 << fact)).zero? ? nil : 0 }
      loop do
        changed = false
        @actions.each do |action|
          values = Strips.members(action.pre).map { |fact| costs[fact] }
          next if values.any?(&:nil?)
          value = action.cost + (maximum ? (values.max || 0) : values.sum)
          Strips.members(action.add).each do |fact|
            if costs[fact].nil? || value < costs[fact]
              costs[fact] = value
              changed = true
            end
          end
        end
        break unless changed
      end
      @cost_cache[key] = costs
    end

    def relaxed_plan(state)
      return @plan_cache[state] if @plan_cache.key?(state)
      costs = relaxed_costs(state, false)
      return @plan_cache[state] = nil if Strips.members(@goal).any? { |fact| costs[fact].nil? }
      chosen, pending = Set.new, Strips.members(@goal & ~state)
      until pending.empty?
        fact = pending.pop
        winner, lowest = nil, nil
        @achievers[fact].each do |number|
          action = @actions[number]
          values = Strips.members(action.pre).map { |pre| costs[pre] }
          next if values.any?(&:nil?)
          cost = action.cost + values.sum
          winner, lowest = number, cost if lowest.nil? || cost < lowest
        end
        next if chosen.include?(winner)
        chosen << winner
        pending.concat(Strips.members(@actions[winner].pre & ~state))
      end
      @plan_cache[state] = chosen.to_a.sort
    end

    def helpful(state)
      (relaxed_plan(state) || []).select { |number| Strips.applicable?(@actions[number], state) }
    end

    def levels(state)
      return @level_cache[state] if @level_cache.key?(state)
      facts = Array.new(@fact_count) { |fact| (state & (1 << fact)).zero? ? nil : 0 }
      actions = Array.new(@actions.length)
      level = 0
      loop do
        changed = false
        @actions.each do |action|
          next unless actions[action.number].nil?
          next if Strips.members(action.pre).any? { |fact| facts[fact].nil? || facts[fact] > level }
          actions[action.number] = level
          Strips.members(action.add).each do |fact|
            next unless facts[fact].nil?
            facts[fact] = level + 1
            changed = true
          end
        end
        break unless changed
        level += 1
      end
      @level_cache[state] = [facts, actions]
    end

    def verified?(state, excluded_fact)
      reachable = state
      loop do
        previous = reachable
        @actions.each do |action|
          next unless (action.add & (1 << excluded_fact)).zero? && Strips.subset?(action.pre, reachable)
          reachable |= action.add
        end
        break if reachable == previous
      end
      !Strips.subset?(@goal, reachable)
    end

    def landmarks(state)
      return @landmark_cache[state] if @landmark_cache.key?(state)
      fact_levels, action_levels = levels(state)
      return @landmark_cache[state] = nil if Strips.members(@goal).any? { |fact| fact_levels[fact].nil? }
      landmarks = @goal & ~state
      pending, verification, head = Strips.members(landmarks), {}, 0
      while head < pending.length
        fact = pending[head]
        head += 1
        earliest = @achievers[fact].select { |number| action_levels[number] == fact_levels[fact] - 1 }
        candidates = earliest.map { |number| @actions[number].pre }.reduce { |first, second| first & second }
        Strips.members(candidates & ~state & ~landmarks).each do |candidate|
          verification[candidate] = verified?(state, candidate) unless verification.key?(candidate)
          next unless verification[candidate]
          landmarks |= 1 << candidate
          pending << candidate
        end
      end
      @landmark_cache[state] = landmarks
    end

    def value(name, state)
      key = [name, state]
      return @value_cache[key] if @value_cache.key?(key)
      value = case name
              when 'none' then 0
              when 'goalcount' then Strips.cardinality(@goal & ~state)
              when 'hmax', 'hadd'
                costs = relaxed_costs(state, name == 'hmax')
                values = Strips.members(@goal).map { |fact| costs[fact] }
                values.any?(&:nil?) ? nil : (name == 'hmax' ? (values.max || 0) : values.sum)
              when 'ff'
                plan = relaxed_plan(state)
                plan && plan.sum { |number| @actions[number].cost }
              else
                facts = landmarks(state)
                facts.nil? ? nil : Strips.cardinality(facts)
              end
      @value_cache[key] = value
    end
    def values(state) = HEURISTIC_NAMES.to_h { |name| [name, value(name, state)] }
  end
end
