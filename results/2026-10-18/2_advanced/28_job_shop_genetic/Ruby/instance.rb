module JobShop
  Operation = Struct.new(:id, :job, :index, :machine, :duration, :head, :tail,
                         :previous, :following, keyword_init: true)
  Job = Struct.new(:number, :operations, :work, keyword_init: true)
  Machine = Struct.new(:operations, :load, :head, :tail, :bound, keyword_init: true)
  Instance = Struct.new(:jobs, :by_job, :operations, :machines, :errors, keyword_init: true) do
    def self.read(path)
      lines = File.readlines(path, chomp: true)
      job_count, machine_count = lines.shift.split.map(&:to_i)
      jobs = []
      operations = []
      errors = []
      lines.first(job_count).each_with_index do |line, job_index|
        number = job_index + 1
        seen = {}
        route = []
        error = nil
        line.split.each_with_index do |token, index|
          machine, duration = token.split(':').map(&:to_i)
          message = if !(1..machine_count).cover?(machine)
                      "unknown machine #{machine}"
                    elsif !(1..99).cover?(duration)
                      "bad duration #{duration}"
                    elsif seen[machine]
                      "repeated machine #{machine}"
                    end
          if message
            error = "job #{number} operation #{index + 1}: #{message}"
            break
          end
          seen[machine] = true
          route << [machine, duration]
        end
        if error
          errors << error
          next
        end
        work = route.sum { |_, duration| duration }
        first = operations.length
        ids = (first...(first + route.length)).to_a
        head = 0
        route.each_with_index do |(machine, duration), index|
          operations << Operation.new(
            id: ids[index], job: number, index: index + 1, machine: machine,
            duration: duration, head: head, tail: work - head - duration,
            previous: index.zero? ? nil : ids[index - 1],
            following: ids[index + 1]
          )
          head += duration
        end
        jobs << Job.new(number: number, operations: ids, work: work)
      end
      machines = Array.new(machine_count + 1)
      (1..machine_count).each do |machine|
        members = operations.select { |operation| operation.machine == machine }
        load = members.sum(&:duration)
        head = members.map(&:head).min
        tail = members.map(&:tail).min
        machines[machine] = Machine.new(
          operations: members.map(&:id), load: load, head: head, tail: tail,
          bound: head + load + tail
        )
      end
      new(jobs: jobs, by_job: jobs.to_h { |job| [job.number, job] },
          operations: operations, machines: machines, errors: errors)
    end
  end
end
