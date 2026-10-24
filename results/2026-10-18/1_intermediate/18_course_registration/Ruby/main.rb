DAYS = %w[MO TU WE TH FR SA SU].freeze
POINTS = {'A' => 4, 'B' => 3, 'C' => 2, 'D' => 1, 'F' => 0}.freeze
Slot = Struct.new(:day, :start, :finish, :raw)
Grade = Struct.new(:code, :grade, :credits)
Student = Struct.new(:id, :year, :limit, :grades, :taking, :history)
Course = Struct.new(:code, :credits, :capacity, :slots, :prerequisite, :open, :enrolled, :waiting)
class CommandError < StandardError; end

def time_text(minutes)
  format('%02d:%02d', minutes / 60, minutes % 60)
end

def overlap?(a, b)
  a.day == b.day && a.start < b.finish && b.start < a.finish
end

def weekly(c)
  c.slots.sum { |s| s.finish - s.start }
end

def earned(s)
  s.grades.reject { |r| r.grade == 'F' }.sum(&:credits)
end

def passed(s, code)
  s.grades.find { |r| r.code == code && %w[A B C].include?(r.grade) }
end

def rate(k, m)
  m.positive? ? "#{k * 100 / m}%" : 'n/a'
end

def gpa(s)
  return 'n/a' if s.grades.empty?
  p = s.grades.sum { |r| POINTS[r.grade] * r.credits }
  c = s.grades.sum(&:credits)
  v = (200 * p + c) / (2 * c)
  format('%d.%02d', v / 100, v % 100)
end

def combine(kind, children)
  flat = children.flat_map { |c| c[:kind] == kind ? c[:children] : [c] }
  flat.length == 1 ? flat.first : {kind: kind, children: flat}
end

def canonical(node)
  return '-' if node.nil?
  return node[:word] if node[:kind] == :leaf
  node[:children].map do |c|
    node[:kind] == :and && c[:kind] == :or ? "(#{canonical(c)})" : canonical(c)
  end.join(node[:kind] == :and ? '&' : '|')
end

def contains?(node, code)
  return false if node.nil?
  node[:kind] == :leaf ? node[:word] == code : node[:children].any? { |c| contains?(c, code) }
end

def satisfied?(node, s)
  return true if node.nil?
  if node[:kind] == :leaf
    return /\AY[1-9]\z/.match?(node[:word]) ? s.year >= node[:word][1].to_i : !passed(s, node[:word]).nil?
  end
  node[:kind] == :and ? node[:children].all? { |c| satisfied?(c, s) } : node[:children].any? { |c| satisfied?(c, s) }
end

class PrerequisiteParser
  def initialize(code, text)
    @code = code
    @tokens = text.scan(/[A-Z0-9]+|[&|()]/)
    @position = 0
    @tokens.each do |token|
      invalid unless %w[& | ( )].include?(token) || /\A(?:[A-Z]{2,4}[0-9]{3}|Y[1-9])\z/.match?(token)
    end
  end

  def invalid
    raise CommandError, "invalid prereq #{@code}"
  end

  def factor
    token = @tokens[@position]
    @position += 1
    if token == '('
      node = expression
      invalid unless @tokens[@position] == ')'
      @position += 1
      node
    else
      invalid if token.nil? || %w[& | )].include?(token)
      {kind: :leaf, word: token}
    end
  end

  def term
    nodes = [factor]
    while @tokens[@position] == '&'
      @position += 1
      nodes << factor
    end
    combine(:and, nodes)
  end

  def expression
    nodes = [term]
    while @tokens[@position] == '|'
      @position += 1
      nodes << term
    end
    combine(:or, nodes)
  end

  def parse
    node = expression
    invalid unless @position == @tokens.length
    raise CommandError, "self prereq #{@code}" if contains?(node, @code)
    node
  end
end

def prerequisite(code, text)
  text == '-' ? nil : PrerequisiteParser.new(code, text).parse
end

def slots(text)
  return [] if text == '-'
  result = text.split(',').map do |raw|
    day = raw[0, 2]
    sh, sm, eh, em = [raw[2, 2], raw[4, 2], raw[7, 2], raw[9, 2]].map(&:to_i)
    start = sh * 60 + sm
    finish = eh * 60 + em
    unless DAYS.include?(day) && sh <= 23 && sm <= 59 && eh <= 23 && em <= 59 && start < finish
      raise CommandError, "invalid slot #{raw}"
    end
    Slot.new(day, start, finish, raw)
  end
  result.each_index do |i|
    ((i + 1)...result.length).each do |j|
      raise CommandError, "overlapping slots #{result[i].raw} #{result[j].raw}" if overlap?(result[i], result[j])
    end
  end
  result
end

class Registrar
  attr_reader :output

  def initialize
    @courses = {}
    @students = {}
    @command_number = 0
    @output = []
  end

  def emit(indent, *parts)
    @output << ' ' * indent + parts.join(' ')
  end

  def student(id)
    raise CommandError, "unknown student #{id}" unless @students.key?(id)
    @students[id]
  end

  def course(code)
    raise CommandError, "unknown course #{code}" unless @courses.key?(code)
    @courses[code]
  end

  def sorted_courses
    @courses.values.sort_by(&:code)
  end

  def taking(s, except = nil)
    s.taking.keys.reject { |code| code == except }.sort.map { |code| @courses[code] }
  end

  def credits(s, except = nil)
    taking(s, except).sum(&:credits)
  end

  def waitlists(s)
    sorted_courses.select { |c| c.waiting.include?(s.id) }
  end

  def conflict(s, c, except = nil)
    taking(s, except).find { |other| other.slots.any? { |a| c.slots.any? { |b| overlap?(a, b) } } }
  end

  def eligible(s, c, except = nil)
    return ['course closed', []] unless c.open
    return ['already enrolled', []] if c.enrolled.key?(s.id)
    return ['already waitlisted', []] if c.waiting.include?(s.id)
    grade = passed(s, c.code)
    return ['already completed', [grade.grade]] if grade
    return ['prereq not met', []] unless satisfied?(c.prerequisite, s)
    conflicting = conflict(s, c, except)
    return ['time conflict', [conflicting.code]] if conflicting
    total = credits(s, except) + c.credits
    return ['credit limit', [total, s.limit]] if total > s.limit
    ['OK', []]
  end

  def judgment(s, c)
    result = eligible(s, c)
    return result unless result[0] == 'OK'
    return ['enroll', []] if c.enrolled.length < c.capacity
    return ['waitlist limit', []] if waitlists(s).length >= 3
    ['waitlist', [1 + c.waiting.count { |id| @students[id].year >= s.year }]]
  end

  def reject(s, c, result)
    raise CommandError, [result[0], s.id, c.code, *result[1]].join(' ')
  end

  def history(s, event)
    s.history << [@command_number, event]
  end

  def enroll(s, c)
    c.enrolled[s.id] = true
    s.taking[c.code] = true
  end

  def remove(s, c)
    c.enrolled.delete(s.id)
    s.taking.delete(c.code)
  end

  def enrollment_line(label, s, c, indent = 0)
    emit(indent, label, s.id, c.code, 'enrolled', "#{c.enrolled.length}/#{c.capacity}", 'credits', "#{credits(s)}/#{s.limit}")
  end

  def promote
    sorted_courses.each do |c|
      next unless c.open
      while c.enrolled.length < c.capacity
        index = c.waiting.index do |id|
          s = @students[id]
          conflict(s, c).nil? && credits(s) + c.credits <= s.limit
        end
        break if index.nil?
        s = @students[c.waiting.delete_at(index)]
        enroll(s, c)
        history(s, "promote #{c.code}")
        enrollment_line('PROMOTE', s, c, 2)
      end
    end
  end

  def schedule(s)
    taking = taking(s)
    emit(0, 'SCHEDULE', s.id, 'courses', taking.length, 'credits', credits(s), 'weekly', time_text(taking.sum { |c| weekly(c) }))
    DAYS.each do |day|
      meetings = taking.flat_map { |c| c.slots.select { |slot| slot.day == day }.map { |slot| [c.code, slot] } }
      meetings.sort_by! { |_, slot| slot.start }
      emit(2, day, *meetings.flat_map { |code, slot| ["#{time_text(slot.start)}-#{time_text(slot.finish)}", code] }) unless meetings.empty?
    end
    tba = taking.select { |c| c.slots.empty? }.map(&:code)
    emit(2, 'TBA', *tba) unless tba.empty?
  end

  def command(cmd, a)
    case cmd
    when 'COURSE'
      raise CommandError, "duplicate course #{a[0]}" if @courses.key?(a[0])
      meetings = slots(a[3])
      tree = prerequisite(a[0], a[4])
      c = Course.new(a[0], a[1].to_i, a[2].to_i, meetings, tree, true, {}, [])
      @courses[c.code] = c
      emit(0, 'COURSE', c.code, 'credits', c.credits, 'capacity', c.capacity,
           'meetings', meetings.length, 'weekly', time_text(weekly(c)), 'prereq', canonical(tree))
    when 'STUDENT'
      raise CommandError, "duplicate student #{a[0]}" if @students.key?(a[0])
      grades = []
      seen = {}
      (a[3] == '-' ? [] : a[3].split(',')).each do |token|
        code, grade, credits = token.split(':')
        raise CommandError, "invalid grade #{a[0]} #{code} #{grade}" unless POINTS.key?(grade)
        raise CommandError, "duplicate record #{a[0]} #{code}" if seen.key?(code)
        seen[code] = true
        grades << Grade.new(code, grade, credits.to_i)
      end
      s = Student.new(a[0], a[1].to_i, a[2].to_i, grades, {}, [])
      @students[s.id] = s
      emit(0, 'STUDENT', s.id, 'year', s.year, 'limit', s.limit, 'records', grades.length, 'earned', earned(s), 'gpa', gpa(s))
    when 'ENROLL', 'CHECK'
      s = student(a[0])
      c = course(a[1])
      result = judgment(s, c)
      if cmd == 'CHECK'
        emit(0, 'CHECK', s.id, c.code, result[0], *result[1])
      elsif result[0] == 'enroll'
        enroll(s, c)
        history(s, "enroll #{c.code}")
        enrollment_line('ENROLL', s, c)
      elsif result[0] == 'waitlist'
        position = result[1][0]
        c.waiting.insert(position - 1, s.id)
        history(s, "waitlist #{c.code} #{position}")
        emit(0, 'ENROLL', s.id, c.code, 'waitlist', position)
      else
        reject(s, c, result)
      end
    when 'OPTIONS'
      s = student(a[0])
      emit(0, 'OPTIONS', s.id, 'courses', @courses.length)
      sorted_courses.each do |c|
        result = judgment(s, c)
        emit(2, c.code, result[0], *result[1])
      end
    when 'DROP'
      s = student(a[0])
      c = course(a[1])
      position = c.waiting.index(s.id)
      if c.enrolled.key?(s.id)
        remove(s, c)
        history(s, "drop #{c.code}")
        enrollment_line('DROP', s, c)
      elsif position
        c.waiting.delete_at(position)
        history(s, "drop #{c.code} waitlist")
        emit(0, 'DROP', s.id, c.code, 'waitlist', 'removed')
      else
        raise CommandError, "not registered #{s.id} #{c.code}"
      end
      promote
    when 'SWAP'
      s = student(a[0])
      old = course(a[1])
      following = course(a[2])
      raise CommandError, "not enrolled #{s.id} #{old.code}" unless old.enrolled.key?(s.id)
      raise CommandError, "same course #{old.code}" if old.equal?(following)
      result = eligible(s, following, old.code)
      reject(s, following, result) unless result[0] == 'OK'
      raise CommandError, "course full #{following.code}" if following.enrolled.length >= following.capacity
      remove(s, old)
      enroll(s, following)
      history(s, "swap #{old.code} #{following.code}")
      emit(0, 'SWAP', s.id, old.code, '->', following.code, 'credits', "#{credits(s)}/#{s.limit}")
      promote
    when 'CLOSE', 'OPEN'
      c = course(a[0])
      if c.open == (cmd == 'OPEN')
        raise CommandError, "already #{cmd == 'CLOSE' ? 'closed' : 'open'} #{c.code}"
      end
      c.open = cmd == 'OPEN'
      emit(0, cmd, c.code, 'enrolled', "#{c.enrolled.length}/#{c.capacity}", 'waitlist', c.waiting.length)
      promote if cmd == 'OPEN'
    when 'CAPACITY'
      c = course(a[0])
      capacity = a[1].to_i
      raise CommandError, "capacity below enrollment #{c.code} #{c.enrolled.length}" if capacity < c.enrolled.length
      old = c.capacity
      c.capacity = capacity
      emit(0, 'CAPACITY', c.code, old, '->', capacity)
      promote
    when 'LIMIT'
      s = student(a[0])
      limit = a[1].to_i
      total = credits(s)
      raise CommandError, "limit below enrolled #{s.id} #{total}" if limit < total
      old = s.limit
      s.limit = limit
      emit(0, 'LIMIT', s.id, old, '->', limit)
      promote
    when 'PREREQ'
      c = course(a[0])
      tree = prerequisite(c.code, a[1])
      c.prerequisite = tree
      emit(0, 'PREREQ', c.code, canonical(tree))
      c.waiting = c.waiting.select do |id|
        s = @students[id]
        if satisfied?(tree, s)
          true
        else
          history(s, "unlist #{c.code}")
          emit(2, 'UNLIST', s.id, c.code)
          false
        end
      end
    when 'CANCEL'
      c = course(a[0])
      emit(0, 'CANCEL', c.code, 'enrolled', c.enrolled.length, 'waitlist', c.waiting.length)
      c.enrolled.each_key do |id|
        s = @students[id]
        s.taking.delete(c.code)
        history(s, "cancel #{c.code}")
      end
      c.waiting.each { |id| history(@students[id], "cancel #{c.code} waitlist") }
      @courses.delete(c.code)
      promote
    when 'ROSTER'
      c = course(a[0])
      emit(0, 'ROSTER', c.code, c.open ? 'open' : 'closed', 'enrolled', "#{c.enrolled.length}/#{c.capacity}", 'waitlist', c.waiting.length)
      c.enrolled.keys.sort.each { |id| emit(2, 'enrolled', id, 'year', @students[id].year) }
      c.waiting.each_with_index { |id, i| emit(2, 'waitlist', i + 1, id, 'year', @students[id].year) }
    when 'SCHEDULE'
      schedule(student(a[0]))
    when 'FREE'
      s = student(a[0])
      raise CommandError, "invalid day #{a[1]}" unless DAYS.include?(a[1])
      meetings = taking(s).flat_map(&:slots).select { |t| t.day == a[1] && t.start < 1320 && t.finish > 480 }.sort_by(&:start)
      ranges = []
      cursor = 480
      meetings.each do |slot|
        start = [slot.start, 480].max
        ranges << [cursor, start] if start > cursor
        cursor = [cursor, [slot.finish, 1320].min].max
      end
      ranges << [cursor, 1320] if cursor < 1320
      emit(0, 'FREE', s.id, a[1], 'total', time_text(ranges.sum { |x, y| y - x }),
           *ranges.map { |x, y| "#{time_text(x)}-#{time_text(y)}" })
    when 'INFO'
      c = course(a[0])
      emit(0, 'INFO', c.code, c.open ? 'open' : 'closed', 'credits', c.credits, 'capacity', c.capacity, 'prereq', canonical(c.prerequisite))
      c.slots.sort_by { |t| [DAYS.index(t.day), t.start] }.each do |slot|
        emit(2, 'meet', slot.day, "#{time_text(slot.start)}-#{time_text(slot.finish)}")
      end
      emit(2, 'meet', 'TBA') if c.slots.empty?
      required = sorted_courses.select { |other| contains?(other.prerequisite, c.code) }.map(&:code)
      emit(2, 'required', 'by', *(required.empty? ? ['none'] : required))
    when 'AUDIT'
      s = student(a[0])
      emit(0, 'AUDIT', s.id, 'year', s.year, 'limit', s.limit)
      s.grades.sort_by(&:code).each { |r| emit(2, 'record', r.code, r.grade, r.credits) }
      emit(2, 'earned', earned(s), 'gpa', gpa(s))
      taking(s).each { |c| emit(2, 'enrolled', c.code, c.credits) }
      emit(2, 'credits', credits(s), 'remaining', s.limit - credits(s))
      waitlists(s).each { |c| emit(2, 'waitlist', c.code, c.waiting.index(s.id) + 1) }
    when 'HISTORY'
      s = student(a[0])
      emit(0, 'HISTORY', s.id, 'events', s.history.length)
      s.history.each { |command, event| emit(2, command, event) }
    when 'STUDENTS'
      emit(0, 'STUDENTS', @students.length)
      @students.values.sort_by(&:id).each do |s|
        emit(2, s.id, 'year', s.year, 'credits', "#{credits(s)}/#{s.limit}", 'courses', s.taking.length, 'waitlists', waitlists(s).length)
      end
    when 'REPORT'
      courses = sorted_courses
      enrolled = courses.sum { |c| c.enrolled.length }
      capacity = courses.sum(&:capacity)
      waiting = courses.sum { |c| c.waiting.length }
      emit(0, 'REPORT', 'courses', courses.length, 'enrolled', "#{enrolled}/#{capacity}", 'rate', rate(enrolled, capacity), 'waitlisted', waiting)
      courses.each do |c|
        emit(2, c.code, c.open ? 'open' : 'closed', "#{c.enrolled.length}/#{c.capacity}", rate(c.enrolled.length, c.capacity), 'waitlist', c.waiting.length)
      end
      courses.group_by { |c| c.code[0...-3] }.sort.each do |department, group|
        k = group.sum { |c| c.enrolled.length }
        m = group.sum(&:capacity)
        emit(2, 'dept', department, 'courses', group.length, 'enrolled', "#{k}/#{m}", 'rate', rate(k, m),
             'waitlisted', group.sum { |c| c.waiting.length })
      end
    end
  end

  def execute(line)
    @command_number += 1
    cmd, *args = line.split
    begin
      command(cmd, args)
    rescue CommandError => error
      emit(0, 'ERROR', error.message)
    end
  end
end

registrar = Registrar.new
STDIN.gets.to_i.times { registrar.execute(STDIN.gets.chomp) }
STDOUT.write(registrar.output.join("\n") + "\n")
