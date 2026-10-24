require_relative 'rational'

module BranchBound
  Node = Struct.new(:lower, :upper, :depth, :parent, :branch, :parent_value)

  def self.search(model, limit, &solve)
    stack = [Node.new(model[:lower].dup, model[:upper].dup, 0, nil, 'root', nil)]
    solves, lines, incumbent, objective, status = [], [], nil, nil, nil
    incumbents = pruned = infeasible = 0
    until stack.empty?
      if solves.length == limit
        status = 'NODE_LIMIT'
        break
      end
      node = stack.pop
      number = solves.length + 1
      result = solve.call(node.lower, node.upper, number)
      solves << result
      if result[:status] == 'INFEASIBLE'
        outcome = 'infeasible'
        infeasible += 1
      elsif result[:status] == 'UNBOUNDED'
        outcome, status = 'unbounded', 'UNBOUNDED'
      elsif objective && (model[:direction] == 'maximize' ? result[:objective] <= objective : result[:objective] >= objective)
        outcome = 'pruned'
        pruned += 1
      else
        fractional = model[:integer].each_index.find { |j| model[:integer][j] && result[:solution][j].denominator != 1 }
        if fractional.nil?
          incumbent, objective, outcome = result[:solution].dup, result[:objective], 'incumbent'
          incumbents += 1
        else
          value, name = result[:solution][fractional], model[:variables][fractional]
          down, up = value.floor, value.ceil
          lower, upper = node.lower.dup, node.upper.dup
          lower[fractional], upper[fractional] = Rational(up), Rational(down)
          stack << Node.new(lower, node.upper.dup, node.depth + 1, number, "#{name}>=#{up}", result[:objective])
          stack << Node.new(node.lower.dup, upper, node.depth + 1, number, "#{name}<=#{down}", result[:objective])
          outcome = "branch #{name} #{Q.f(value)}"
        end
      end
      lp = result[:status] == 'OPTIMAL' ? Q.f(result[:objective]) : result[:status].downcase
      lines << "NODE #{number} depth #{node.depth} parent #{node.parent || '-'} branch #{node.branch} lp #{lp} pivots #{result[:pivots]} action #{outcome}"
      break if status == 'UNBOUNDED'
    end
    status ||= incumbent ? 'OPTIMAL' : 'INFEASIBLE'
    if status == 'NODE_LIMIT'
      stack.reverse_each { |node| lines << "OPEN parent #{node.parent} branch #{node.branch} bound #{Q.f(node.parent_value)}" }
      bounds = stack.map(&:parent_value)
      bounds << objective if objective
      bound = model[:direction] == 'maximize' ? bounds.max : bounds.min
    else
      bound = objective
    end
    lines << "RESULT #{status} objective #{Q.f(objective)} nodes #{solves.length} incumbents #{incumbents} pruned #{pruned} infeasible #{infeasible} open #{stack.length} bound #{Q.f(bound)}"
    {status: status, objective: objective, solution: incumbent, solves: solves, root: solves.first,
     nodes: solves.length, lines: lines}
  end
end
