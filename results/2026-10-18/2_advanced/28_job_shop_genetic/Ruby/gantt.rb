module JobShop
  module Gantt
    module_function

    def dimensions(makespan, width)
      power = 1
      loop do
        [1, 2, 5].each do |factor|
          scale = factor * power
          columns = (makespan + scale - 1) / scale
          return [scale, columns] if columns <= width
        end
        power *= 10
      end
    end

    def characters(intervals, scale, columns)
      (0...columns).map do |column|
        left = column * scale
        right = left + scale
        best_overlap = 0
        best_start = nil
        mark = '.'
        intervals.each do |start, finish, candidate|
          overlap = [finish, right].min - [start, left].max
          next unless overlap.positive?
          next if overlap < best_overlap || (overlap == best_overlap && start >= best_start)

          best_overlap = overlap
          best_start = start
          mark = candidate
        end
        mark
      end.join
    end

    def row(label, characters)
      "#{label.ljust(4)} |#{characters}|"
    end

    def build(instance, schedule, path, width)
      scale, columns = dimensions(schedule.makespan, width)
      time = 'time'
      (0...columns).step(10) do |column|
        position = 6 + column
        text = (column * scale).to_s
        time = time.ljust(position)
        time[position, text.length] = text
      end
      lines = [time, '      ' + (0...columns).map { |column| (column % 10).zero? ? '+' : '-' }.join]
      critical = path.to_h { |id| [id, true] }
      (1...instance.machines.length).each do |machine|
        intervals = schedule.order[machine].map do |id|
          letter = (64 + instance.operations[id].job).chr
          letter = letter.downcase if critical[id]
          [schedule.starts[id], schedule.completions[id], letter]
        end
        lines << row("M#{machine}", characters(intervals, scale, columns))
      end
      busy = (0...columns).map do |column|
        time_point = column * scale
        count = (1...instance.machines.length).count do |machine|
          schedule.order[machine].any? do |id|
            schedule.starts[id] <= time_point && time_point < schedule.completions[id]
          end
        end
        count == 10 ? 'X' : count.to_s
      end.join
      lines << row('busy', busy)
      instance.jobs.each do |job|
        intervals = job.operations.map do |id|
          [schedule.starts[id], schedule.completions[id], (instance.operations[id].machine % 10).to_s]
        end
        lines << row("J#{job.number}", characters(intervals, scale, columns))
      end
      { scale: scale, columns: columns, lines: lines }
    end
  end
end
