require_relative 'search'

module Strips
  GraphElement = Struct.new(:number, :pre, :add, :delete)

  class PlanningGraph
    def initialize(actions, initial, goal, limit)
      @actions, @goal, @limit = actions, goal, limit
      @facts, @fact_mutexes = [initial], [Set.new]
      @elements, @element_mutexes, @achievers = [], [], []
      @memo, @lines = Set.new, []
      @searched = @memo_hits = @tried = 0
    end

    def pair(first, second) = first < second ? [first, second] : [second, first]
    def compatible_facts?(facts, mutexes)
      Strips.members(facts).combination(2).none? { |first, second| mutexes.include?([first, second]) }
    end
    def conflict?(first, second, mutexes)
      !(first.delete & (second.pre | second.add)).zero? ||
        !(second.delete & (first.pre | first.add)).zero? ||
        Strips.members(first.pre).any? { |p| Strips.members(second.pre).any? { |q| mutexes.include?(pair(p, q)) } }
    end

    def expand(level)
      facts, mutexes = @facts[level], @fact_mutexes[level]
      elements = @actions.filter_map do |action|
        GraphElement.new(action.number, action.pre, action.add, action.delete) if Strips.subset?(action.pre, facts) && compatible_facts?(action.pre, mutexes)
      end
      action_count = elements.length
      Strips.members(facts).each { |fact| elements << GraphElement.new(nil, 1 << fact, 1 << fact, 0) }
      exclusive = Set.new
      elements.each_index.to_a.combination(2) do |first, second|
        exclusive << [first, second] if conflict?(elements[first], elements[second], mutexes)
      end
      @lines << "action level #{level}: actions=#{action_count} noops=#{Strips.cardinality(facts)} mutexes=#{exclusive.length}"
      achievers = {}
      elements.each_with_index do |element, index|
        Strips.members(element.add).each { |fact| (achievers[fact] ||= []) << index }
      end
      achievers.each_value { |producers| producers.sort_by! { |index| elements[index].number || -1 } }
      following = Strips.mask(achievers.keys)
      following_mutexes = Set.new
      achievers.keys.sort.combination(2) do |first, second|
        if achievers[first].all? { |x| achievers[second].all? { |y| x != y && exclusive.include?(pair(x, y)) } }
          following_mutexes << [first, second]
        end
      end
      @elements << elements
      @element_mutexes << exclusive
      @achievers << achievers
      @facts << following
      @fact_mutexes << following_mutexes
    end

    # Explicit continuations preserve the prescribed recursive search order without
    # using the Ruby call stack for up to thirty fact levels and their goal sets.
    def extract(level, goals)
      stack = [{kind: :extract, level: level, goals: goals, phase: :enter}]
      answer = nil
      until stack.empty?
        frame = stack.last
        j, q = frame.values_at(:level, :goals)
        if frame[:kind] == :extract
          if frame[:phase] == :enter
            if j.zero?
              answer = []
              stack.pop
            elsif @memo.include?([j, q])
              @memo_hits += 1
              answer = nil
              stack.pop
            else
              @searched += 1
              frame[:phase] = :return
              stack << {kind: :assign, level: j, goals: q, position: 0, chosen: [], phase: :enter}
            end
          else
            @memo << [j, q] if answer.nil?
            stack.pop
          end
          next
        end
        elements = @elements[j - 1]
        case frame[:phase]
        when :enter
          position, chosen = frame.values_at(:position, :chosen)
          position += 1 while position < q.length && chosen.any? { |index| !(elements[index].add & (1 << q[position])).zero? }
          frame[:position] = position
          if position == q.length
            previous = chosen.reduce(0) { |facts, index| facts | elements[index].pre }
            frame[:phase] = :previous
            stack << {kind: :extract, level: j - 1, goals: Strips.members(previous), phase: :enter}
          else
            frame[:producers] = @achievers[j - 1].fetch(q[position])
            frame[:next] = 0
            frame[:phase] = :choose
          end
        when :previous
          unless answer.nil?
            layer = frame[:chosen].filter_map { |index| elements[index].number }.sort
            answer = answer + [layer]
          end
          stack.pop
        when :child
          if answer.nil?
            frame[:phase] = :choose
          else
            stack.pop
          end
        when :choose
          producer = nil
          while frame[:next] < frame[:producers].length
            index = frame[:producers][frame[:next]]
            frame[:next] += 1
            next if frame[:chosen].any? { |other| @element_mutexes[j - 1].include?(pair(index, other)) }
            producer = index
            break
          end
          if producer.nil?
            answer = nil
            stack.pop
          else
            @tried += 1
            frame[:phase] = :child
            stack << {kind: :assign, level: j, goals: q, position: frame[:position] + 1,
                      chosen: frame[:chosen] + [producer], phase: :enter}
          end
        end
      end
      answer
    end

    def finish(status, layers = [])
      SearchResult.new(status, @searched, @tried, layers.flatten, layers, @lines, @memo_hits)
    end

    def run
      (0..@limit).each do |level|
        facts, mutexes = @facts[level], @fact_mutexes[level]
        @lines << "fact level #{level}: facts=#{Strips.cardinality(facts)} mutexes=#{mutexes.length}"
        possible = Strips.subset?(@goal, facts) && compatible_facts?(@goal, mutexes)
        if possible
          before_search, before_hits = @searched, @memo_hits
          layers = extract(level, Strips.members(@goal))
          @lines << "extract level #{level}: #{layers.nil? ? 'fail' : 'success'} searched=#{@searched - before_search} memo_hits=#{@memo_hits - before_hits}"
          return finish('solved', layers) unless layers.nil?
        elsif level.positive? && Strips.cardinality(facts) == Strips.cardinality(@facts[level - 1]) && mutexes.length == @fact_mutexes[level - 1].length
          return finish('unreachable')
        end
        return finish('level limit') if level == @limit
        expand(level)
      end
    end
  end
end
