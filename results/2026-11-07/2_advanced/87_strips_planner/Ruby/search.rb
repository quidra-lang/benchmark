require_relative 'grounding'

module Strips
  SearchResult = Struct.new(:status, :expanded, :generated, :plan, :layers, :lines, :memo_hits)
  Node = Struct.new(:state, :g, :depth, :parent, :action)
  def self.applicable?(action, state) = subset?(action.pre, state) && (action.neg & state).zero?
  def self.apply(action, state) = (state & ~action.delete) | action.add
  def self.result(status, expanded = 0, generated = 0, plan = []) = SearchResult.new(status, expanded, generated, plan)
  def self.reconstruct(node)
    plan = []
    until node.parent.nil?
      plan << node.action
      node = node.parent
    end
    plan.reverse
  end
  def self.priority(algorithm, node, heuristic, weight)
    case algorithm
    when 'bfs' then node.depth
    when 'ucs' then node.g
    when 'gbfs' then heuristic
    else node.g + heuristic * (algorithm == 'wastar' ? weight : 1)
    end
  end

  class MinHeap
    def initialize = @items = []
    def empty? = @items.empty?
    def push(item)
      index = @items.length
      @items << item
      while index.positive?
        parent = (index - 1) / 2
        break if (@items[parent][0] <=> item[0]) <= 0
        @items[index] = @items[parent]
        index = parent
      end
      @items[index] = item
    end
    def pop
      first = @items.first
      last = @items.pop
      unless @items.empty?
        index = 0
        while (child = 2 * index + 1) < @items.length
          child += 1 if child + 1 < @items.length && (@items[child + 1][0] <=> @items[child][0]).negative?
          break if (last[0] <=> @items[child][0]) <= 0
          @items[index] = @items[child]
          index = child
        end
        @items[index] = last
      end
      first
    end
  end

  def self.best_first(problem, start, algorithm, heuristic, budget, weight, evaluator)
    initial_h = evaluator.value(heuristic, start)
    return result('dead end') if initial_h.nil?
    first = Node.new(start, 0, 0, nil, nil)
    queue = MinHeap.new
    queue.push([[priority(algorithm, first, initial_h, weight), initial_h, 0], first])
    best, serial, expanded, generated = {start => 0}, 1, 0, 0
    reopen = %w[ucs astar wastar].include?(algorithm)
    until queue.empty?
      _, node = queue.pop
      next if reopen && node.g > best[node.state]
      return result('solved', expanded, generated, reconstruct(node)) if subset?(problem.goal, node.state)
      return result('budget', expanded, generated) if expanded == budget
      expanded += 1
      problem.actions.each do |action|
        next unless applicable?(action, node.state)
        state = apply(action, node.state)
        generated += 1
        cost = node.g + action.cost
        next if best.key?(state) && (!reopen || best[state] <= cost)
        best[state] = cost
        value = evaluator.value(heuristic, state)
        next if value.nil?
        child = Node.new(state, cost, node.depth + 1, node, action.number)
        queue.push([[priority(algorithm, child, value, weight), value, serial], child])
        serial += 1
      end
    end
    result('exhausted', expanded, generated)
  end

  def self.hill_climbing(problem, start, heuristic, budget, evaluator)
    current, plan = start, []
    current_h = evaluator.value(heuristic, current)
    expanded = generated = 0
    return result('dead end') if current_h.nil?
    until subset?(problem.goal, current)
      queue, visited, improved, head = [[current, []]], Set[current], false, 0
      while head < queue.length && !improved
        state, prefix = queue[head]
        head += 1
        return result('budget', expanded, generated) if expanded == budget
        expanded += 1
        evaluator.helpful(state).each do |number|
          successor = apply(problem.actions[number], state)
          generated += 1
          next if visited.include?(successor)
          visited << successor
          value = evaluator.value(heuristic, successor)
          next if value.nil?
          path = prefix + [number]
          if value < current_h
            plan.concat(path)
            current, current_h, improved = successor, value, true
            break
          end
          queue << [successor, path]
        end
      end
      return result('stuck', expanded, generated) unless improved
    end
    result('solved', expanded, generated, plan)
  end

  def self.run(problem, start, algorithm, heuristic, budget, weight, evaluator)
    algorithm == 'ehc' ? hill_climbing(problem, start, heuristic, budget, evaluator) : best_first(problem, start, algorithm, heuristic, budget, weight, evaluator)
  end
end
