# frozen_string_literal: true

require_relative 'enrolment'
require_relative 'conflict_graph'
require_relative 'coloring'
require_relative 'rooms'
require_relative 'report'

class ExamTimetable
  PAIR_NAMES = %w[BACK_TO_BACK SAME_DAY OVERNIGHT].freeze

  def initialize
    @errors = []
    data = Enrolment.read(@errors)
    @courses, @students, @enrolments = data.courses, data.students, data.enrolments
    @rooms = Rooms.read(@errors)
    @graph = ConflictGraph.new(@courses, @students)
    @largest_room = @rooms.map(&:capacity).max
    @empty = @courses.keys.select { |id| @courses[id].count.zero? }.sort
    @oversized = @courses.keys.select { |id| @courses[id].count > @largest_room }.sort
    @schedulable = (@courses.keys - @empty - @oversized).sort
    @schedulable_set = @schedulable.to_h { |id| [id, true] }
    @closed = {}
    @unavailable = @students.to_h { |student, _ids| [student, {}] }
    @fixed = {}
    @orders = []
    read_calendar
    @queries = File.readlines('input/queries.txt', chomp: true)
  end

  def read_calendar
    lines = File.readlines('input/calendar.txt', chomp: true)
    @days = lines[0].split[1].to_i
    @periods = lines[1].split.drop(1).map(&:to_i)
    @limit = lines[2].split[1].to_i
    @weights = lines[3].split.drop(1).map(&:to_i)
    front_count, @deadline = lines[4].split.drop(1).map(&:to_i)
    @ratio = lines[5].split[1].to_i
    @slots = (1..@days * @periods.length).to_a
    @front = @schedulable.sort_by { |id| [-@courses[id].count, id] }.first(front_count)
    lines.drop(6).each_with_index do |line, index|
      kind, *values = line.split
      message = case kind
                when 'closed' then accept_closed(*values.map(&:to_i))
                when 'unavailable' then accept_unavailable(values[0], *values.drop(1).map(&:to_i))
                when 'fixed' then accept_fixed(values[0], *values.drop(1).map(&:to_i))
                when 'after' then accept_order(*values)
                end
      @errors << "calendar.txt line #{index + 7}: #{message}" if message
    end
    @open_slots = @slots.reject { |slot| @closed[slot] }
  end

  def slot_name(slot)
    "D#{day(slot)}P#{(slot - 1) % @periods.length + 1}"
  end

  def day(slot)
    (slot - 1).div(@periods.length) + 1
  end

  def slot_length(slot)
    @periods[(slot - 1) % @periods.length]
  end

  def in_range?(date, period)
    date.between?(1, @days) && period.between?(1, @periods.length)
  end

  def accept_closed(date, period)
    return "slot #{date} #{period} outside calendar" unless in_range?(date, period)

    slot = (date - 1) * @periods.length + period
    return "duplicate closed #{slot_name(slot)}" if @closed[slot]

    @closed[slot] = true
    nil
  end

  def accept_unavailable(student, date, period)
    return "unknown student #{student}" unless @students.key?(student)
    return "slot #{date} #{period} outside calendar" unless in_range?(date, period)

    slot = (date - 1) * @periods.length + period
    return "duplicate unavailable #{student} #{slot_name(slot)}" if @unavailable[student][slot]

    @unavailable[student][slot] = true
    nil
  end

  def accept_fixed(id, date, period)
    return "unknown course #{id}" unless @courses.key?(id)
    return "course #{id} not schedulable" unless @schedulable_set[id]
    return "slot #{date} #{period} outside calendar" unless in_range?(date, period)

    slot = (date - 1) * @periods.length + period
    return "slot #{slot_name(slot)} closed" if @closed[slot]
    return "slot #{slot_name(slot)} unsuitable for #{id}" unless suitable?(id, slot)
    return "duplicate fixed #{id}" if @fixed.key?(id)

    ids = courses_at(@fixed, slot)
    conflict = ids.select { |other| @graph.neighbours[id].key?(other) }.min
    return "conflict #{id} #{conflict}" if conflict
    return "rooms full #{slot_name(slot)}" unless pack(ids + [id])

    @fixed[id] = slot
    nil
  end

  def accept_order(first, second)
    unknown = [first, second].find { |id| !@courses.key?(id) }
    return "unknown course #{unknown}" if unknown

    unsuitable = [first, second].find { |id| !@schedulable_set[id] }
    return "course #{unsuitable} not schedulable" if unsuitable
    return "bad order #{first} #{second}" if first == second
    return "duplicate order #{first} #{second}" if @orders.include?([first, second])
    return "cycle #{first} #{second}" if ConflictGraph.reachable?(@orders, second, first)

    if @fixed.key?(first) && @fixed.key?(second) && @fixed[first] <= @fixed[second]
      return "fixed order #{first} #{second}"
    end
    @orders << [first, second]
    nil
  end

  def suitable?(id, slot)
    slot_length(slot) >= @courses[id].duration &&
      @courses[id].students.none? { |student| @unavailable[student][slot] }
  end

  def courses_at(assignment, slot)
    assignment.keys.select { |id| assignment[id] == slot }
  end

  def pack(ids)
    Rooms.pack(ids, @courses, @rooms)
  end

  def order_violations(id, slot, assignment)
    @orders.each_with_object([]) do |(first, second), result|
      if first == id && assignment.key?(second) && slot <= assignment[second]
        result << second
      elsif second == id && assignment.key?(first) && slot >= assignment[first]
        result << first
      end
    end
  end

  def orders_valid?(assignment)
    @orders.all? do |first, second|
      !assignment.key?(first) || !assignment.key?(second) || assignment[first] > assignment[second]
    end
  end

  def candidate_slots(id, assignment)
    @open_slots.select do |slot|
      suitable?(id, slot) &&
        @graph.neighbours[id].keys.none? { |other| assignment[other] == slot } &&
        order_violations(id, slot, assignment).empty? && pack(courses_at(assignment, slot) + [id])
    end
  end

  def rejected_slot_reason(id, slot)
    return 'closed' if @closed[slot]
    return 'too_short' if slot_length(slot) < @courses[id].duration

    unavailable = @courses[id].students.find { |student| @unavailable[student][slot] }
    return "unavailable #{unavailable}" if unavailable

    neighbours = @graph.neighbours[id]
    conflict = neighbours.keys.select { |other| @assignment[other] == slot }
                         .min_by { |other| [-neighbours[other], other] }
    return "conflict #{conflict} shared #{neighbours[conflict]}" if conflict

    other = order_violations(id, slot, @assignment).min
    other ? "order #{other}" : 'rooms'
  end

  def build_timetable
    excluded = {}
    @attempts = []
    loop do
      remaining = @schedulable.reject { |id| @fixed.key?(id) || excluded[id] }
      attempt = Coloring::Attempt.new(remaining, @fixed, @graph, method(:candidate_slots), @limit).run
      @attempts << { courses: remaining.length, backtracks: attempt[:backtracks],
                     success: attempt[:success], dead_end: attempt[:dead_end] }
      if attempt[:success]
        @assignment = attempt[:assignment]
        @assignment_order = attempt[:order]
        break
      end
      excluded[attempt[:dead_end]] = true
    end
    @excluded = excluded.keys.sort
  end

  def insert_excluded
    @insertions = []
    @reasons = {}
    @excluded.each do |id|
      candidates = candidate_slots(id, @assignment)
      if candidates.empty?
        @reasons[id] = @slots.map { |slot| rejected_slot_reason(id, slot) }
        next
      end
      before = score(@assignment)[:total]
      after, slot = candidates.map { |candidate| [score(@assignment.merge(id => candidate))[:total], candidate] }.min
      @assignment[id] = slot
      @insertions << { course: id, slot: slot, increase: after - before }
    end
    @unscheduled = (@oversized + @excluded.reject { |id| @assignment.key?(id) }).sort
    @initial = score(@assignment)
    @penalty = @initial[:total]
  end

  def relation(first, second)
    first, second = second, first if second < first
    difference = second - first
    if day(first) == day(second)
      return 0 if difference == 1
      return 1 if difference >= 2
    elsif difference == 1
      return 2
    end
    nil
  end

  def score(assignment)
    counts = Array.new(4, 0)
    contributions = Hash.new(0)
    per_day = Array.new(@days + 1) { Array.new(3, 0) }
    @graph.edges.each do |first, second, shared|
      next unless assignment.key?(first) && assignment.key?(second)

      kind = relation(assignment[first], assignment[second])
      next unless kind

      counts[kind] += shared
      per_day[day([assignment[first], assignment[second]].min)][kind] += shared
      contribution = @weights[kind] * shared
      contributions[first] += contribution
      contributions[second] += contribution
    end
    late = @front.select { |id| assignment.key?(id) && assignment[id] > @deadline }
    counts[3] = late.length
    late.each { |id| contributions[id] += @weights[3] }
    { counts: counts, total: counts.zip(@weights).sum { |count, weight| count * weight },
      contributions: contributions, days: per_day, late: late }
  end

  def exchange_slots
    @rounds = []
    serial = 0
    loop do
      counts = Hash.new(0)
      exchanges = []
      @open_slots.combination(2) do |first, second|
        counts[:pairs] += 1
        if @fixed.value?(first) || @fixed.value?(second)
          counts[:fixed] += 1
          next
        end
        moved = @assignment.keys.select { |id| [first, second].include?(@assignment[id]) }
        trial = @assignment.dup
        moved.each { |id| trial[id] = @assignment[id] == first ? second : first }
        if moved.any? { |id| !suitable?(id, trial[id]) } || !orders_valid?(trial)
          counts[:invalid] += 1
          next
        end
        after = score(trial)[:total]
        if after >= @penalty
          counts[:worse] += 1
          next
        end
        counts[:applied] += 1
        serial += 1
        exchanges << { serial: serial, first: first, second: second, before: @penalty, after: after }
        @assignment = trial
        @penalty = after
      end
      @rounds << { counts: counts, exchanges: exchanges }
      break if counts[:applied].zero?
    end
    @exchanged = score(@assignment)
  end

  def swap_kempe_chains
    @passes = []
    serial = 0
    loop do
      counts = Hash.new(0)
      swaps = []
      @assignment.keys.reject { |id| @fixed.key?(id) }.sort.each do |id|
        first = @assignment[id]
        @open_slots.each do |second|
          next if second == first

          counts[:candidates] += 1
          chain = @graph.kempe(id, first, second, @assignment)
          if chain.any? { |course| @fixed.key?(course) }
            counts[:fixed] += 1
            next
          end
          trial = @assignment.dup
          chain.each { |course| trial[course] = @assignment[course] == first ? second : first }
          if chain.any? { |course| !suitable?(course, trial[course]) } || !orders_valid?(trial)
            counts[:invalid] += 1
            next
          end
          unless pack(courses_at(trial, first)) && pack(courses_at(trial, second))
            counts[:rooms] += 1
            next
          end
          after = score(trial)[:total]
          if after >= @penalty
            counts[:worse] += 1
            next
          end
          counts[:applied] += 1
          serial += 1
          moves = chain.map { |course| [course, @assignment[course], trial[course]] }
          swaps << { serial: serial, course: id, first: first, second: second, moves: moves,
                     before: @penalty, after: after }
          @assignment = trial
          @penalty = after
          break
        end
      end
      @passes << { counts: counts, swaps: swaps }
      break if counts[:applied].zero?
    end
    @final = score(@assignment)
  end

  def assign_rooms
    @placements = {}
    @slot_info = {}
    @room_info = @rooms.to_h { |room| [room.id, { slots: 0, exams: 0, seated: 0 }] }
    @open_slots.each do |slot|
      placements = pack(courses_at(@assignment, slot))
      @placements.merge!(placements)
      room_counts = Hash.new(0)
      placements.each do |id, placement|
        count = @courses[id].count
        room_counts[placement.room.id] += count
        @room_info[placement.room.id][:exams] += 1
        @room_info[placement.room.id][:seated] += count
      end
      room_counts.each_key { |id| @room_info[id][:slots] += 1 }
      used = @rooms.select { |room| room_counts.key?(room.id) }
      @slot_info[slot] = { courses: placements.keys, placements: placements,
                           students: room_counts.values.sum, rooms: used.length,
                           seats: used.sum(&:capacity),
                           invigilators: room_counts.values.sum { |count| (count + @ratio - 1).div(@ratio) } }
    end
  end

  def student_statistics
    @student_info = {}
    @histogram = Hash.new(0)
    @gaps = Hash.new(0)
    @dayloads = Hash.new(0)
    @students.each do |student, ids|
      assigned = ids.select { |id| @assignment.key?(id) }.sort_by { |id| [@assignment[id], id] }
      counts = Array.new(3, 0)
      pairs = []
      assigned.combination(2) do |first, second|
        kind = relation(@assignment[first], @assignment[second])
        next unless kind

        counts[kind] += 1
        pairs << [first, second, kind]
      end
      total = counts.zip(@weights.first(3)).sum { |count, weight| count * weight }
      @histogram[total] += 1
      assigned.each_cons(2) { |first, second| @gaps[@assignment[second] - @assignment[first]] += 1 }
      per_day = Hash.new(0)
      assigned.each { |id| per_day[day(@assignment[id])] += 1 }
      @dayloads[per_day.values.max] += 1 unless assigned.empty?
      @student_info[student] = { assigned: assigned, unassigned: ids.reject { |id| @assignment.key?(id) },
                                 counts: counts, total: total, pairs: pairs }
    end
  end

  def timetable_lines
    lines = ["TIMETABLE days #{@days} periods #{@periods.length} open #{@open_slots.length} courses #{@courses.length} scheduled #{@assignment.length} unscheduled #{@unscheduled.length} empty #{@empty.length}"]
    columns = (1..@periods.length).map { |period| "P#{period}" } + ['TOTAL']
    lines << Report.table('DAY', columns, 4, 10)
    1.upto(@days) do |date|
      exams = 0
      students = 0
      values = (1..@periods.length).map do |period|
        slot = (date - 1) * @periods.length + period
        next 'closed' if @closed[slot]

        info = @slot_info[slot]
        exams += info[:courses].length
        students += info[:students]
        "#{info[:courses].length}/#{info[:students]}"
      end
      lines << Report.table("D#{date}", values + ["#{exams}/#{students}"], 4, 10)
    end
    @slots.each do |slot|
      heading = "SLOT #{slot} #{slot_name(slot)} minutes #{slot_length(slot)}"
      if @closed[slot]
        lines << heading + ' closed'
        next
      end
      info = @slot_info[slot]
      lines << heading + " exams #{info[:courses].length} students #{info[:students]} rooms #{info[:rooms]} seats #{info[:seats]} invigilators #{info[:invigilators]}"
      info[:placements].each do |id, placement|
        course = @courses[id]
        fixed = @fixed.key?(id) ? ' fixed' : ''
        lines << "  #{id} #{course.duration}min students #{course.count} room #{placement.room.id} seats #{placement.first}-#{placement.last}#{fixed} #{course.name}"
      end
    end
    @rooms.each do |room|
      info = @room_info[room.id]
      utilization = Report.percentage(info[:seated], room.capacity * @open_slots.length)
      lines << "ROOM #{room.id} capacity #{room.capacity} slots #{info[:slots]} exams #{info[:exams]} seated #{info[:seated]} utilization #{utilization}"
    end
    lines << "INVIGILATORS total #{@slot_info.values.sum { |info| info[:invigilators] }} ratio #{@ratio}"
    lines
  end

  def room_lines
    lines = ['slot,room,course,students,first_seat,last_seat']
    @open_slots.each do |slot|
      @rooms.each do |room|
        placements = @slot_info[slot][:placements].select { |_id, placement| placement.room == room }
        placements.sort_by { |_id, placement| placement.first }.each do |id, placement|
          lines << [slot_name(slot), room.id, id, @courses[id].count, placement.first, placement.last].join(',')
        end
      end
    end
    lines
  end

  def breakdown(score)
    counts = score[:counts]
    "back_to_back #{counts[0]} same_day #{counts[1]} overnight #{counts[2]} front_load #{counts[3]} penalty #{score[:total]}"
  end

  def penalty_lines
    lines = ["WEIGHTS back_to_back #{@weights[0]} same_day #{@weights[1]} overnight #{@weights[2]} front_load #{@weights[3]}",
             "FRONT_LOAD courses #{@front.length} last_slot #{slot_name(@deadline)}", "INITIAL #{breakdown(@initial)}"]
    @rounds.each_with_index do |round, index|
      counts = round[:counts]
      lines << "ROUND #{index + 1} pairs #{counts[:pairs]} fixed #{counts[:fixed]} invalid #{counts[:invalid]} worse #{counts[:worse]} applied #{counts[:applied]}"
      round[:exchanges].each do |exchange|
        lines << "EXCHANGE #{exchange[:serial]} #{slot_name(exchange[:first])} #{slot_name(exchange[:second])} penalty #{exchange[:before]} -> #{exchange[:after]}"
      end
    end
    lines << "EXCHANGED #{breakdown(@exchanged)}"
    @passes.each_with_index do |pass, index|
      counts = pass[:counts]
      lines << "PASS #{index + 1} candidates #{counts[:candidates]} fixed #{counts[:fixed]} invalid #{counts[:invalid]} rooms #{counts[:rooms]} worse #{counts[:worse]} applied #{counts[:applied]}"
      pass[:swaps].each do |swap|
        lines << "SWAP #{swap[:serial]} #{swap[:course]} #{slot_name(swap[:first])} #{slot_name(swap[:second])} chain #{swap[:moves].length} penalty #{swap[:before]} -> #{swap[:after]}"
        swap[:moves].each { |id, first, second| lines << "  MOVE #{id} #{slot_name(first)} -> #{slot_name(second)}" }
      end
    end
    lines << "FINAL #{breakdown(@final)}"
    lines << "SAVED #{@initial[:total] - @final[:total]}"
    1.upto(@days) do |date|
      counts = @final[:days][date]
      lines << "DAY D#{date} back_to_back #{counts[0]} same_day #{counts[1]} overnight #{counts[2]}"
    end
    @final[:late].each { |id| lines << "LATE #{id} #{slot_name(@assignment[id])} students #{@courses[id].count}" }
    @assignment.keys.sort_by { |id| [-@final[:contributions][id], id] }.first(10).each do |id|
      contribution = @final[:contributions][id]
      lines << "COURSE #{id} #{slot_name(@assignment[id])} penalty #{contribution}" if contribution > 0
    end
    [['HISTOGRAM', @histogram], ['GAP', @gaps], ['DAYLOAD', @dayloads]].each do |label, values|
      values.sort.each { |value, count| lines << "#{label} #{value} #{count}" }
    end
    @students.keys.sort_by { |student| [-@student_info[student][:total], student] }.first(5).each do |student|
      info = @student_info[student]
      next if info[:total].zero?

      counts = info[:counts]
      lines << "WORST #{student} penalty #{info[:total]} back_to_back #{counts[0]} same_day #{counts[1]} overnight #{counts[2]}"
    end
    lines
  end

  def student_lines
    lines = []
    @queries.each do |student|
      unless @students.key?(student)
        lines << "STUDENT #{student} not found"
        next
      end
      info = @student_info[student]
      lines << "STUDENT #{student} exams #{@students[student].length} scheduled #{info[:assigned].length} penalty #{info[:total]}"
      info[:assigned].each do |id|
        course = @courses[id]
        placement = @placements[id]
        seat = placement.first + course.students.index(student)
        lines << "  #{slot_name(@assignment[id])} #{id} room #{placement.room.id} seat #{seat} #{course.name}"
      end
      info[:unassigned].each { |id| lines << "  UNSCHEDULED #{id} #{@courses[id].name}" }
      info[:pairs].each do |first, second, kind|
        lines << "  #{PAIR_NAMES[kind]} #{slot_name(@assignment[first])} #{first} #{slot_name(@assignment[second])} #{second}"
      end
      @unavailable[student].keys.sort.each { |slot| lines << "  UNAVAILABLE #{slot_name(slot)}" }
    end
    lines
  end

  def course_lines
    lines = ['course,status,slot,students,minutes,degree,penalty']
    @courses.keys.sort.each do |id|
      status = if @fixed.key?(id)
                 'fixed'
               elsif @assignment.key?(id)
                 'scheduled'
               elsif @oversized.include?(id)
                 'too_large'
               elsif @empty.include?(id)
                 'empty'
               else
                 'no_slot'
               end
      slot = @assignment.key?(id) ? slot_name(@assignment[id]) : '-'
      lines << [id, status, slot, @courses[id].count, @courses[id].duration,
                @graph.degree(id), @final[:contributions][id]].join(',')
    end
    lines
  end

  def report_lines
    lines = ["INPUT courses #{@courses.length} enrolments #{@enrolments} rooms #{@rooms.length} students #{@students.length} errors #{@errors.length}"]
    @errors.each { |error| lines << "ERROR #{error}" }
    vertices, edges = @graph.vertices, @graph.edges
    density = vertices.length < 2 ? 0 : (2000 * edges.length).div(vertices.length * (vertices.length - 1))
    lines << "GRAPH courses #{vertices.length} edges #{edges.length} shared #{edges.sum { |_a, _b, count| count }} density #{density}"
    vertices.sort_by { |id| [-@graph.degree(id), id] }.first(5).each do |id|
      lines << "DEGREE #{id} neighbours #{@graph.degree(id)} shared #{@graph.neighbours[id].values.sum} students #{@courses[id].count}"
    end
    components = @graph.components
    lines << "COMPONENTS #{components.length}"
    components.each_with_index { |group, index| lines << "COMPONENT #{index + 1} size #{group.length} first #{group.first}" }
    clique = @graph.clique(@schedulable)
    lines << ['CLIQUE', 'size', clique.length, *clique].join(' ')
    maximum = @students.values.map(&:length).max
    lines << "LOAD max_exams #{maximum} students #{@students.values.count { |ids| ids.length == maximum }}"
    demand = @schedulable.sum { |id| @courses[id].count }
    capacity = @rooms.sum(&:capacity)
    lines << "SEATS demand #{demand} capacity #{capacity} min_slots #{(demand + capacity - 1).div(capacity)}"
    degree_order = @schedulable.sort_by { |id| [-@graph.degree(id), id] }
    enrolment_order = @schedulable.sort_by { |id| [-@courses[id].count, id] }
    lines << "HEURISTIC largest_degree slots #{Coloring.greedy(degree_order, @graph)}"
    lines << "HEURISTIC largest_enrolment slots #{Coloring.greedy(enrolment_order, @graph)}"
    table = vertices.sort_by { |id| [-@courses[id].count, id] }.first(8)
    lines << Report.table('MATRIX', table, 9, 9)
    table.each do |id|
      values = table.map { |other| id == other ? '-' : @graph.neighbours[id].fetch(other, 0) }
      lines << Report.table(id, values, 9, 9)
    end
    @empty.each { |id| lines << "EMPTY #{id}" }
    @oversized.each { |id| lines << "TOO_LARGE #{id} students #{@courses[id].count} largest_room #{@largest_room}" }
    @closed.keys.sort.each { |slot| lines << "CLOSED #{slot_name(slot)}" }
    @fixed.keys.sort.each { |id| lines << "FIXED #{id} #{slot_name(@fixed[id])}" }
    @orders.each { |first, second| lines << "AFTER #{first} #{second}" }
    @attempts.each_with_index do |attempt, index|
      result = attempt[:success] ? 'success' : "failed #{attempt[:dead_end]}"
      lines << "ATTEMPT #{index + 1} courses #{attempt[:courses]} backtracks #{attempt[:backtracks]} #{result}"
    end
    @assignment_order.each_with_index do |entry, index|
      lines << "ORDER #{index + 1} #{entry[:course]} #{slot_name(entry[:slot])} saturation #{entry[:saturation]} degree #{@graph.degree(entry[:course])}"
    end
    @insertions.each do |entry|
      lines << "INSERTED #{entry[:course]} #{slot_name(entry[:slot])} penalty #{entry[:increase]}"
    end
    @unscheduled.each do |id|
      reason = @oversized.include?(id) ? 'too_large' : 'no_slot'
      lines << "UNSCHEDULED #{id} reason #{reason} students #{@courses[id].count}"
      next unless reason == 'no_slot'

      @reasons[id].each_with_index { |message, index| lines << "  #{slot_name(index + 1)} #{message}" }
    end
    used = @slot_info.count { |_slot, info| !info[:courses].empty? }
    lines << "SUMMARY scheduled #{@assignment.length} unscheduled #{@unscheduled.length} slots_used #{used} penalty #{@final[:total]}"
    lines
  end

  def run
    build_timetable
    insert_excluded
    exchange_slots
    swap_kempe_chains
    assign_rooms
    student_statistics
    Report.write('timetable.txt', timetable_lines)
    Report.write('rooms.csv', room_lines)
    Report.write('penalties.txt', penalty_lines)
    Report.write('student_schedules.txt', student_lines)
    Report.write('course_status.csv', course_lines)
    Report.write('report.txt', report_lines)
  end
end

ExamTimetable.new.run if $PROGRAM_NAME == __FILE__
