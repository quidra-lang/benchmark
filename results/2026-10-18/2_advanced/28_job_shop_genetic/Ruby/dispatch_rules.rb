module JobShop
  module DispatchRules
    module_function

    def build(instance, rule, positions = nil)
      operations = instance.operations
      next_index = Hash.new(0)
      ready = Hash.new(0)
      free = Array.new(instance.machines.length, 0)
      starts = Array.new(operations.length)
      decisions = 0
      ties = 0
      operations.length.times do
        available = instance.jobs.filter_map do |job|
          id = job.operations[next_index[job.number]]
          next if id.nil?

          operation = operations[id]
          earliest = [ready[job.number], free[operation.machine]].max
          priority = case rule
                     when 'SPT' then operation.duration
                     when 'LPT' then -operation.duration
                     when 'MWKR' then -(operation.duration + operation.tail)
                     when 'FIFO' then ready[job.number]
                     when 'GENES' then positions[id]
                     end
          [id, earliest, earliest + operation.duration, priority]
        end
        first = available.min_by { |id, _, completion, _| [completion, operations[id].machine] }
        completion = first[2]
        machine = operations[first[0]].machine
        conflict = available.select do |id, earliest, _, _|
          operations[id].machine == machine && earliest < completion
        end
        choice = conflict.min_by { |id, _, _, priority| [priority, operations[id].job] }
        decisions += 1 if conflict.length >= 2
        ties += 1 if conflict.count { |candidate| candidate[3] == choice[3] } >= 2
        id, earliest = choice
        operation = operations[id]
        starts[id] = earliest
        ready[operation.job] = free[machine] = earliest + operation.duration
        next_index[operation.job] += 1
      end
      { starts: starts, decisions: decisions, ties: ties }
    end
  end
end
