module JobShop
  module Genetic
    module_function

    def decode(instance, chromosome)
      next_index = Hash.new(0)
      ready = Hash.new(0)
      free = Array.new(instance.machines.length, 0)
      starts = Array.new(instance.operations.length)
      chromosome.each do |number|
        id = instance.by_job.fetch(number).operations[next_index[number]]
        operation = instance.operations[id]
        starts[id] = [ready[number], free[operation.machine]].max
        ready[number] = free[operation.machine] = starts[id] + operation.duration
        next_index[number] += 1
      end
      starts
    end

    def tournament(values, size, random)
      Array.new(size) { random.below(values.length) }.min_by { |index| [values[index], index] }
    end

    def crossover(first, second, jobs, random)
      selected = {}
      jobs.each { |job| selected[job.number] = true if random.below(2).zero? }
      [crossed_child(first, second, selected), crossed_child(second, first, selected)]
    end

    def crossed_child(fixed, donor, selected)
      remaining = donor.reject { |gene| selected[gene] }
      index = 0
      fixed.map do |gene|
        if selected[gene]
          gene
        else
          value = remaining[index]
          index += 1
          value
        end
      end
    end

    def swap(chromosome, random)
      first = random.below(chromosome.length)
      second = random.below(chromosome.length)
      chromosome[first], chromosome[second] = chromosome[second], chromosome[first]
    end

    def insert(chromosome, random)
      first = random.below(chromosome.length)
      second = random.below(chromosome.length)
      gene = chromosome.delete_at(first)
      chromosome.insert(second, gene)
    end
  end
end
