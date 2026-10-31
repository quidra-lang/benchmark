SEX_INDEX = { 'M' => 0, 'F' => 1, 'X' => 2 }.freeze
ORDINALS = %w[first second third fourth fifth sixth seventh eighth ninth tenth].freeze
TERMS = {
  'parent' => %w[father mother parent], 'child' => %w[son daughter child],
  'sibling' => %w[brother sister sibling], 'pibling' => %w[uncle aunt pibling],
  'nibling' => %w[nephew niece nibling], 'spouse' => %w[husband wife spouse],
  'late' => ['late husband', 'late wife', 'late spouse'],
  'survivor' => ['widower', 'widow', 'surviving spouse'],
  'ex' => %w[ex-husband ex-wife ex-spouse],
  'stepparent' => %w[stepfather stepmother stepparent],
  'stepchild' => %w[stepson stepdaughter stepchild],
  'stepsibling' => %w[stepbrother stepsister stepsibling],
  'stepgrandparent' => %w[stepgrandfather stepgrandmother stepgrandparent],
  'stepgrandchild' => %w[stepgrandson stepgranddaughter stepgrandchild],
  'parent-in-law' => %w[father-in-law mother-in-law parent-in-law],
  'child-in-law' => %w[son-in-law daughter-in-law child-in-law],
  'sibling-in-law' => %w[brother-in-law sister-in-law sibling-in-law]
}.freeze
STEPS = {
  'parent' => ['parent', nil], 'father' => ['parent', 'M'], 'mother' => ['parent', 'F'],
  'child' => ['child', nil], 'son' => ['child', 'M'], 'daughter' => ['child', 'F'],
  'sibling' => ['sibling', nil], 'brother' => ['sibling', 'M'], 'sister' => ['sibling', 'F'],
  'spouse' => ['spouse', nil], 'husband' => ['spouse', 'M'], 'wife' => ['spouse', 'F']
}.freeze
MODIFYING = %w[PERSON DEATH REMOVE PARENT UNPARENT SPOUSE DIVORCE].freeze

class CommandError < StandardError; end

def gendered(kind, sex)
  TERMS[kind][SEX_INDEX[sex]]
end

def generation_prefix(generations)
  generations == 1 ? '' : 'great-' * (generations - 2) + 'grand'
end

def ordinal(number)
  return ORDINALS[number - 1] if number <= 10

  suffix = if [11, 12, 13].include?(number % 100)
             'th'
           else
             { 1 => 'st', 2 => 'nd', 3 => 'rd' }.fetch(number % 10, 'th')
           end
  "#{number}#{suffix}"
end

def kinship_term(da, db, sex)
  return 'self' if da.zero? && db.zero?
  return generation_prefix(db) + gendered('parent', sex) if da.zero?
  return generation_prefix(da) + gendered('child', sex) if db.zero?
  return gendered('sibling', sex) if da == 1 && db == 1
  return generation_prefix(db - 1) + gendered('pibling', sex) if da == 1
  return generation_prefix(da - 1) + gendered('nibling', sex) if db == 1

  distance = (da - db).abs
  removal = case distance
            when 0 then ''
            when 1 then ' once removed'
            when 2 then ' twice removed'
            else " #{distance} times removed"
            end
  ordinal([da, db].min - 1) + ' cousin' + removal
end

def fraction_text(value)
  "#{value.numerator}/#{value.denominator}"
end

Person = Struct.new(:id, :sex, :birth, :name, :death, :parents) do
  def life_years
    "#{birth}-#{death}"
  end
end

Marriage = Struct.new(:first, :second, :start, :finish, :status, :died) do
  def contains?(id)
    id == first || id == second
  end

  def other(id)
    id == first ? second : first
  end
end

Apex = Struct.new(:person, :da, :db, :shares) do
  def blood_term(sex)
    prefix = if shares == 1
               'half-'
             elsif shares >= 4
               'double '
             else
               ''
             end
    prefix + kinship_term(da, db, sex)
  end
end

class Family
  attr_reader :persons
  attr_accessor :marriages

  def initialize
    @persons = {}
    @marriages = []
    reset_cache
  end

  def reset_cache
    @distances = {}
    @children = {}
    @records = {}
    @partners = {}
    @coefficients = {}
  end

  def person(id)
    @persons.fetch(id) { raise CommandError, "UNKNOWN PERSON #{id}" }
  end

  def sex(id)
    @persons[id].sex
  end

  def age_key(id)
    [@persons[id].birth, id]
  end

  def person_list(ids)
    ids.empty? ? '-' : ids.sort_by { |id| age_key(id) }.join(' ')
  end

  def parents(id)
    @persons[id].parents
  end

  def children(id)
    @children[id] ||= @persons.keys.select { |child| parents(child).include?(id) }
  end

  def common_parents(a, b)
    (parents(a) & parents(b)).length
  end

  def siblings?(a, b)
    a != b && common_parents(a, b).positive?
  end

  def siblings(id)
    @persons.keys.select { |other| siblings?(id, other) }
  end

  def common_child?(a, b)
    @persons.each_value.any? { |person| person.parents.include?(a) && person.parents.include?(b) }
  end

  def records_of(id)
    @records[id] ||= @marriages.select { |record| record.contains?(id) }
  end

  def current_record(id)
    records_of(id).find { |record| record.status == 'current' }
  end

  def spouse(id)
    current_record(id)&.other(id)
  end

  def last_record(a, b)
    records_of(a).reverse.find { |record| record.contains?(b) }
  end

  def partners(id)
    @partners[id] ||= begin
      latest = {}
      records_of(id).each { |record| latest[record.other(id)] = record }
      latest.keys.reject { |other| latest[other].status == 'divorced' }
    end
  end

  def step_related?(parents_a, parents_b)
    parents_a.any? { |parent| (partners(parent) & parents_b).any? }
  end

  def generation_distances(start, upward)
    @distances[[start, upward]] ||= begin
      distances = { start => 0 }
      queue = [start]
      index = 0
      while index < queue.length
        id = queue[index]
        index += 1
        neighbors = upward ? parents(id) : children(id)
        neighbors.each do |other|
          next if distances.key?(other)

          distances[other] = distances[id] + 1
          queue << other
        end
      end
      distances
    end
  end

  def lineage(id, upward)
    generation_distances(id, upward).filter_map do |other, distance|
      [distance, other] unless other == id
    end.sort
  end

  def ancestor?(a, b)
    a != b && generation_distances(b, true).key?(a)
  end

  def grandparents(id)
    generation_distances(id, true).filter_map { |other, distance| other if distance == 2 }
  end

  def apex(a, b)
    up_a = generation_distances(a, true)
    up_b = generation_distances(b, true)
    return Apex.new(a, 0, up_b[a], 0) if up_b.key?(a)
    return Apex.new(b, up_a[b], 0, 0) if up_a.key?(b)

    common = up_a.keys & up_b.keys
    return nil if common.empty?

    chosen = common.min_by { |id| [up_a[id] + up_b[id], up_a[id], id] }
    da = up_a[chosen]
    db = up_b[chosen]
    shares = common.count { |id| up_a[id] == da && up_b[id] == db }
    Apex.new(chosen, da, db, shares)
  end

  def relationship(a, b, term_sex = sex(a))
    return ['self'] if a == b

    terms = []
    apex = apex(a, b)
    terms << apex.blood_term(term_sex) if apex
    record = last_record(a, b)
    if record.nil?
      terms << 'co-parent' if common_child?(a, b)
    elsif record.status == 'current'
      terms << gendered('spouse', term_sex)
    elsif record.status == 'widowed'
      terms << gendered(record.died == a ? 'late' : 'survivor', term_sex)
    else
      terms << gendered('ex', term_sex)
    end
    parents_a = parents(a)
    parents_b = parents(b)
    partners_a = partners(a)
    partners_b = partners(b)
    if !parents_b.include?(a) && (partners_a & parents_b).any?
      terms << gendered('stepparent', term_sex)
    end
    if !parents_a.include?(b) && (partners_b & parents_a).any?
      terms << gendered('stepchild', term_sex)
    end
    if common_parents(a, b).zero? && step_related?(parents_a, parents_b)
      terms << gendered('stepsibling', term_sex)
    end
    if !ancestor?(a, b) && (partners_a & grandparents(b)).any?
      terms << gendered('stepgrandparent', term_sex)
    end
    if !ancestor?(b, a) && (partners_b & grandparents(a)).any?
      terms << gendered('stepgrandchild', term_sex)
    end
    terms << gendered('parent-in-law', term_sex) if partners_b.any? { |other| parents(other).include?(a) }
    terms << gendered('child-in-law', term_sex) if partners_a.any? { |other| parents(other).include?(b) }
    if partners_b.any? { |other| siblings?(a, other) } || partners_a.any? { |other| siblings?(other, b) }
      terms << gendered('sibling-in-law', term_sex)
    end
    terms
  end

  def relationship_text(a, b)
    terms = relationship(a, b)
    terms.empty? ? 'no relation' : terms.join(', ')
  end

  def kinship(a, b)
    key = [a, b].sort
    @coefficients[key] ||= if a == b
                            (1 + inbreeding(a)) / 2
                          else
                            x, y = @persons[a].birth >= @persons[b].birth ? [a, b] : [b, a]
                            parents(x).sum(Rational(0)) { |parent| kinship(parent, y) } / 2
                          end
  end

  def inbreeding(id)
    ps = parents(id)
    ps.length == 2 ? kinship(ps[0], ps[1]) : Rational(0)
  end

  def lineage_length(id, memo)
    memo[id] ||= 1 + (parents(id).map { |parent| lineage_length(parent, memo) }.max || 0)
  end

  def upward_path(start, apex)
    route = [start]
    until route.last == apex
      current = route.last
      distance = generation_distances(current, true)[apex]
      candidates = parents(current).select do |parent|
        generation_distances(parent, true)[apex] == distance - 1
      end
      route << candidates.min
    end
    route
  end

  def census_status(id, year)
    record = records_of(id).reverse.find { |marriage| marriage.start <= year }
    return 'single' unless record
    return "married #{record.other(id)}" if record.finish.nil? || record.finish > year

    record.status
  end

  def step_targets(id, kind)
    case kind
    when 'parent' then parents(id)
    when 'child' then children(id)
    when 'sibling' then siblings(id)
    when 'spouse' then [spouse(id)].compact
    end
  end
end

class KinshipCalculator
  def initialize
    @family = Family.new
    @history = []
  end

  def execute(line)
    command, *args = line.split(' ')
    @family.reset_cache
    saved = Marshal.dump(@family) if MODIFYING.include?(command)
    lines = process(command, args)
    @history << [line, saved] if MODIFYING.include?(command)
    lines
  rescue CommandError => error
    ["ERROR #{error.message}"]
  end

  def process(command, args)
    case command
    when 'PERSON' then add_person(*args)
    when 'DEATH' then record_death(*args)
    when 'REMOVE' then remove_person(*args)
    when 'PARENT' then link_parent(*args)
    when 'UNPARENT' then unlink_parent(*args)
    when 'SPOUSE' then marry(*args)
    when 'DIVORCE' then divorce(*args)
    when 'UNDO'
      raise CommandError, 'NOTHING TO UNDO' if @history.empty?

      line, saved = @history.pop
      @family = Marshal.load(saved)
      ["UNDONE #{line}"]
    when 'INFO' then info(*args)
    when 'RELATION'
      a, b = checked(*args)
      ["RELATION #{a} #{b}: #{@family.relationship_text(a, b)}"]
    when 'RELATIVES' then relatives(*args)
    when 'WHO' then who(args.shift, args.join(' '))
    when 'PATH' then path(*args)
    when 'COMMON' then common(*args)
    when 'ANCESTORS' then lineage(args.first, true)
    when 'DESCENDANTS' then lineage(args.first, false)
    when 'COUSINS' then cousins(*args)
    when 'SIBLINGS' then siblings(*args)
    when 'GENERATIONS' then generations(*args)
    when 'TREE' then tree(*args)
    when 'PEDIGREE' then pedigree(*args)
    when 'TIMELINE' then timeline(*args)
    when 'CENSUS' then census(*args)
    when 'KINSHIP'
      a, b = checked(*args)
      ["KINSHIP #{a} #{b} #{fraction_text(@family.kinship(a, b))}"]
    when 'FIND' then find(*args)
    when 'TERM'
      da, db, sex = args
      ["TERM #{da} #{db} #{sex} #{kinship_term(da.to_i, db.to_i, sex)}"]
    when 'STATS' then stats
    when 'AUDIT' then audit
    end
  end

  def checked(*ids)
    ids.each { |id| @family.person(id) }
    ids
  end

  def add_person(id, sex, birth, name)
    raise CommandError, "DUPLICATE PERSON #{id}" if @family.persons.key?(id)

    @family.persons[id] = Person.new(id, sex, birth.to_i, name, nil, [])
    ["ADDED #{id} #{name} #{sex} #{birth}"]
  end

  def record_death(id, year)
    year = year.to_i
    person = @family.person(id)
    raise CommandError, "ALREADY DECEASED #{id}" if person.death

    years = [person.birth] + @family.records_of(id).flat_map { |record| [record.start, record.finish].compact }
    raise CommandError, "BAD YEAR #{id}" if year < years.max

    late = @family.children(id).select { |child| @family.persons[child].birth > year + 1 }.min
    raise CommandError, "AFTER DEATH #{late} #{id}" if late

    person.death = year
    record = @family.current_record(id)
    return ["DIED #{id} #{year}"] unless record

    record.finish = year
    record.status = 'widowed'
    record.died = id
    ["DIED #{id} #{year} spouse=#{record.other(id)}"]
  end

  def remove_person(id)
    checked(id)
    @family.persons.each_value { |person| person.parents.delete(id) }
    @family.marriages.reject! { |record| record.contains?(id) }
    @family.persons.delete(id)
    ["REMOVED #{id}"]
  end

  def link_parent(child_id, parent_id)
    child = @family.person(child_id)
    parent = @family.person(parent_id)
    raise CommandError, "SAME PERSON #{child_id}" if child_id == parent_id
    raise CommandError, "ALREADY PARENT #{child_id} #{parent_id}" if child.parents.include?(parent_id)
    raise CommandError, "TOO MANY PARENTS #{child_id}" if child.parents.length == 2
    raise CommandError, "CYCLE #{child_id} #{parent_id}" if @family.ancestor?(child_id, parent_id)
    raise CommandError, "AGE GAP #{child_id} #{parent_id}" if parent.birth + 12 > child.birth
    if parent.death && parent.death + 1 < child.birth
      raise CommandError, "AFTER DEATH #{child_id} #{parent_id}"
    end
    child.parents << parent_id
    ["LINKED #{child_id} #{parent_id} #{gendered('parent', parent.sex)}"]
  end

  def unlink_parent(child_id, parent_id)
    checked(child_id, parent_id)
    parents = @family.parents(child_id)
    raise CommandError, "NOT PARENT #{child_id} #{parent_id}" unless parents.include?(parent_id)

    parents.delete(parent_id)
    ["UNLINKED #{child_id} #{parent_id}"]
  end

  def marry(a, b, year)
    checked(a, b)
    year = year.to_i
    raise CommandError, "SAME PERSON #{a}" if a == b

    [a, b].each { |id| raise CommandError, "DECEASED #{id}" if @family.persons[id].death }
    [a, b].each { |id| raise CommandError, "ALREADY MARRIED #{id}" if @family.spouse(id) }
    if @family.ancestor?(a, b) || @family.ancestor?(b, a) || @family.siblings?(a, b)
      raise CommandError, "CLOSE KIN #{a} #{b}"
    end
    [a, b].each do |id|
      raise CommandError, "TOO YOUNG #{id}" if year < @family.persons[id].birth + 16
    end
    [a, b].each do |id|
      if @family.records_of(id).any? { |record| record.finish && record.finish >= year }
        raise CommandError, "BAD YEAR #{id}"
      end
    end
    @family.marriages << Marriage.new(a, b, year, nil, 'current', nil)
    ["MARRIED #{a} #{b} #{year}"]
  end

  def divorce(a, b, year)
    checked(a, b)
    year = year.to_i
    raise CommandError, "NOT MARRIED #{a} #{b}" unless @family.spouse(a) == b

    record = @family.current_record(a)
    raise CommandError, "BAD YEAR #{a}" if year <= record.start

    record.finish = year
    record.status = 'divorced'
    ["DIVORCED #{a} #{b} #{year}"]
  end

  def info(id)
    person = @family.person(id)
    lines = ["INFO #{id} #{person.name} #{person.sex} #{person.life_years}",
             "  parents: #{@family.person_list(person.parents)}"]
    @family.records_of(id).each do |record|
      lines << "  marriage: #{record.other(id)} #{record.start}-#{record.finish} #{record.status}"
    end
    lines << "  children: #{@family.person_list(@family.children(id))}"
    lines << "  siblings: #{@family.person_list(@family.siblings(id))}"
    lines << "  inbreeding: #{fraction_text(@family.inbreeding(id))}"
    lines
  end

  def relatives(id)
    checked(id)
    lines = @family.persons.keys.sort.filter_map do |other|
      next if other == id

      terms = @family.relationship(other, id)
      "  #{other}: #{terms.join(', ')}" unless terms.empty?
    end
    ["RELATIVES #{id} #{lines.length}"] + lines
  end

  def who(id, query)
    checked(id)
    lines = @family.persons.keys.sort.filter_map do |other|
      next if other == id

      terms = @family.relationship(other, id)
      neutral = @family.relationship(other, id, 'X')
      index = terms.each_index.find { |i| terms[i] == query || neutral[i] == query }
      "  #{other}: #{terms[index]}" if index
    end
    ["WHO #{id} #{query} #{lines.length}"] + lines
  end

  def path(a, b)
    checked(a, b)
    apex = @family.apex(a, b)
    return ["PATH #{a} #{b} none"] unless apex

    route = @family.upward_path(a, apex.person) + @family.upward_path(b, apex.person)[0...-1].reverse
    ["PATH #{a} #{b} #{apex.da + apex.db}: #{route.join(' ')}"]
  end

  def common(a, b)
    checked(a, b)
    up_a = @family.generation_distances(a, true)
    up_b = @family.generation_distances(b, true)
    shared = up_a.keys & up_b.keys
    nearest = shared.reject { |id| (@family.children(id) & shared).any? }
    nearest.sort_by! { |id| [up_a[id] + up_b[id], id] }
    ["COMMON #{a} #{b} #{nearest.length}"] + nearest.map { |id| "  #{id} #{up_a[id]} #{up_b[id]}" }
  end

  def lineage(id, upward)
    checked(id)
    entries = @family.lineage(id, upward)
    command = upward ? 'ANCESTORS' : 'DESCENDANTS'
    lines = entries.map do |distance, other|
      da, db = upward ? [0, distance] : [distance, 0]
      "  #{distance} #{other} #{kinship_term(da, db, @family.sex(other))}"
    end
    ["#{command} #{id} #{entries.length}"] + lines
  end

  def cousins(id, degree)
    checked(id)
    degree = degree.to_i
    entries = @family.persons.keys.filter_map do |other|
      next if other == id

      apex = @family.apex(other, id)
      next unless apex && apex.da >= 2 && apex.db >= 2 && [apex.da, apex.db].min - 1 == degree

      [(apex.da - apex.db).abs, other, apex.blood_term(@family.sex(other))]
    end.sort
    ["COUSINS #{id} #{degree} #{entries.length}"] + entries.map { |_, other, term| "  #{other} #{term}" }
  end

  def siblings(id)
    checked(id)
    earlier = 0
    lines = @family.persons.keys.sort_by { |other| @family.age_key(other) }.filter_map do |other|
      next if other == id

      shared = @family.common_parents(id, other)
      kind = if shared == 2
               'full'
             elsif shared == 1
               'half'
             elsif @family.step_related?(@family.parents(id), @family.parents(other))
               'step'
             end
      next unless kind

      if kind != 'step' && (@family.age_key(other) <=> @family.age_key(id)).negative?
        earlier += 1
      end
      "  #{other} #{kind} #{@family.persons[other].birth}"
    end
    ["SIBLINGS #{id} #{lines.length} order=#{earlier + 1}"] + lines
  end

  def generations(id)
    checked(id)
    groups = @family.lineage(id, false).group_by(&:first)
    lines = groups.keys.sort.map do |distance|
      people = groups[distance].map { |_, other| @family.persons[other] }
      births = people.map(&:birth)
      "  #{distance} #{people.length} #{people.count { |person| person.death.nil? }} #{births.min}-#{births.max}"
    end
    ["GENERATIONS #{id} #{groups.length}"] + lines
  end

  def tree(id)
    checked(id)
    lines = []
    visit(id, 0, lines, {})
    ["TREE #{id} #{@family.lineage(id, false).length}"] + lines
  end

  def visit(id, depth, lines, visited)
    indent = '  ' * (depth + 1)
    if visited[id]
      lines << "#{indent}#{id} (see above)"
      return
    end
    visited[id] = true
    person = @family.persons[id]
    line = "#{indent}#{id} #{person.name} #{person.life_years}"
    spouse = @family.spouse(id)
    line += " = #{spouse}" if spouse
    lines << line
    @family.children(id).sort_by { |child| @family.age_key(child) }.each do |child|
      visit(child, depth + 1, lines, visited)
    end
  end

  def pedigree(id, depth)
    checked(id)
    depth = depth.to_i
    lines = []
    entered = {}
    enter(id, 1, 0, depth, lines, entered)
    ["PEDIGREE #{id} #{depth} entries=#{lines.length} distinct=#{entered.length}"] + lines
  end

  def enter(id, number, generation, depth, lines, entered)
    person = @family.persons[id]
    lines << "#{'  ' * (generation + 1)}#{number} #{id} #{person.name} #{person.life_years}"
    entered[id] = true
    return unless generation < depth

    parents = person.parents.sort_by { |parent| [SEX_INDEX[@family.sex(parent)], parent] }
    parents.each_with_index do |parent, index|
      enter(parent, 2 * number + index, generation + 1, depth, lines, entered)
    end
  end

  def timeline(id)
    person = @family.person(id)
    events = [[person.birth, 0, '', 'born']]
    @family.records_of(id).each do |record|
      other = record.other(id)
      events << [record.start, 1, other, "married #{other}"]
      if record.status == 'divorced'
        events << [record.finish, 3, other, "divorced #{other}"]
      elsif record.status == 'widowed' && record.died == other
        events << [record.finish, 4, other, "widowed #{other}"]
      end
    end
    children = @family.children(id)
    children.each { |child| events << [@family.persons[child].birth, 2, child, "child #{child}"] }
    [['parent', person.parents], ['child', children]].each do |label, relatives|
      relatives.each do |other|
        death = @family.persons[other].death
        next unless death && death >= person.birth && (person.death.nil? || death <= person.death)

        events << [death, 5, other, "lost #{label} #{other}"]
      end
    end
    events << [person.death, 6, '', 'died'] if person.death
    events.sort_by! { |event| event[0, 3] }
    ["TIMELINE #{id} #{events.length}"] + events.map { |year, _, _, text| "  #{year} #{text}" }
  end

  def census(year)
    year = year.to_i
    residents = @family.persons.keys.select do |id|
      person = @family.persons[id]
      person.birth <= year && (person.death.nil? || person.death > year)
    end.sort_by { |id| @family.age_key(id) }
    lines = residents.map do |id|
      "  #{id} #{year - @family.persons[id].birth} #{@family.census_status(id, year)}"
    end
    ["CENSUS #{year} #{residents.length}"] + lines
  end

  def find(id, route)
    checked(id)
    current = [id]
    route.split('.').each do |step|
      kind, sex = STEPS[step]
      current = current.flat_map { |other| @family.step_targets(other, kind) }.uniq
      current.select! { |other| @family.sex(other) == sex } if sex
    end
    current.delete(id)
    lines = current.sort.map do |other|
      "  #{other}: #{@family.relationship_text(other, id)}"
    end
    ["FIND #{id} #{route} #{current.length}"] + lines
  end

  def stats
    people = @family.persons.values
    living = people.count { |person| person.death.nil? }
    links = people.sum { |person| person.parents.length }
    couples = @family.marriages.count { |record| record.status == 'current' }
    founders = people.count { |person| person.parents.empty? }
    memo = {}
    longest = @family.persons.keys.map { |id| @family.lineage_length(id, memo) }.max || 0
    ["STATS persons=#{people.length} living=#{living} links=#{links} " \
     "couples=#{couples} founders=#{founders} generations=#{longest}"]
  end

  def audit
    lines = @family.marriages.filter_map do |record|
      apex = @family.apex(record.first, record.second)
      if apex
        "  marriage #{record.first} #{record.second} #{apex.blood_term(@family.sex(record.first))}"
      end
    end
    @family.persons.keys.sort.each do |id|
      coefficient = @family.inbreeding(id)
      lines << "  inbred #{id} #{fraction_text(coefficient)}" unless coefficient.zero?
    end
    ["AUDIT #{lines.length}"] + lines
  end
end

calculator = KinshipCalculator.new
$stdin.gets.to_i.times { puts calculator.execute($stdin.gets.chomp) }
