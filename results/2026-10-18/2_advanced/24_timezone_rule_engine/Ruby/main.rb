# frozen_string_literal: true

require 'set'
require_relative 'tz_parser'
require_relative 'day_rules'
require_relative 'transitions'
require_relative 'resolver'
require_relative 'report'

class TimezoneEngine
  Record = Struct.new(:number, :kind, :fields, :block, :previous, :field_error, :error, :value, keyword_init: true)
  KINDS = { 'Rule' => :rule, 'Zone' => :zone, 'Link' => :link }.freeze
  ARGUMENTS = { 'TOUTC' => %i[zone local], 'TOLOCAL' => %i[zone ut],
                'CONVERT' => %i[zone zone local], 'OFFSET' => %i[zone ut],
                'TRANSITIONS' => %i[zone year year], 'DURATION' => %i[zone local local] }.freeze

  def read_input
    params = File.readlines('input/params.txt', chomp: true).map { |line| line.split(' ') }
    @reference = TzParser.timestamp(params[0][1], true)
    @workday = params[1].drop(1).map { |time| TzParser.hms(time) }
    @queries = File.readlines('input/queries.txt', chomp: true)
    @records = []
    @blocks = []
    previous = nil
    File.readlines('input/tzdata.txt', chomp: true).each_with_index do |line, index|
      parsed = TzParser.extract(line)
      next unless parsed

      fields = parsed[:fields]
      kind = parsed[:continued] ? :continuation : KINDS.fetch(fields[0], :unknown)
      record = Record.new(number: index + 1, kind: kind, fields: fields, previous: previous)
      if kind == :zone
        record.block = @blocks.length
        @blocks << { name: fields[1], records: [record] }
      elsif kind == :continuation && previous && !previous.block.nil?
        eligible = (previous.kind == :zone && previous.fields.length >= 6) ||
                   (previous.kind == :continuation && previous.fields.length >= 4)
        if eligible
          record.block = previous.block
          @blocks[record.block][:records] << record
        end
      end
      @records << record
      previous = record
    end
  end

  def check_rule(record)
    fields = record.fields
    first = TzParser.year(fields[2])
    return 'bad year' if first.nil?

    last = TzParser.to_year(fields[3], first)
    return 'bad year' if last.nil?
    return 'syntax error' unless fields[4] == '-'

    month = TzParser.month(fields[5])
    return 'bad month' if month.nil?

    day = TzParser.day(fields[6], month)
    return 'bad day spec' if day.nil?

    at = TzParser.time(fields[7])
    return 'bad time' if at.nil?

    save = TzParser.save(fields[8])
    return 'bad save' if save.nil?

    letter = TzParser.letter(fields[9])
    return 'bad letter' if letter.nil?

    record.value = { line: record.number, name: fields[1], from: first, to: last, month: month,
                     day: day, at: at, save: save, letter: letter, raw: fields }
    nil
  end

  def check_zone_fields(record)
    fields = record.kind == :zone ? record.fields.drop(2) : record.fields
    offset = TzParser.offset(fields[0])
    return 'bad offset' if offset.nil?

    token = fields[1]
    if token == '-'
      kind = :none
      rules = 0
    elsif /\A[0-9]/.match?(token)
      kind = :fixed
      rules = TzParser.save(token)
      return 'bad save' if rules.nil?
    else
      kind = :named
      rules = token
    end
    return 'bad format' unless TzParser.format?(fields[2], kind == :named)

    limit, error = TzParser.until_fields(fields.drop(3))
    return error if error

    record.value = { offset: offset, rules_kind: kind, rules: rules, format: fields[2], until: limit }
    nil
  end

  def check_fields(record)
    count = record.fields.length
    case record.kind
    when :rule
      count == 10 ? check_rule(record) : 'syntax error'
    when :zone
      count.between?(5, 9) ? check_zone_fields(record) : 'syntax error'
    when :continuation
      if record.block.nil? || !count.between?(3, 7)
        'syntax error'
      else
        check_zone_fields(record)
      end
    when :link
      count == 3 ? nil : 'syntax error'
    else
      'syntax error'
    end
  end

  def structural_error(record, seen)
    if record.kind == :zone
      name = record.fields[1]
      return "duplicate zone #{name}" if seen.include?(name)

      seen.add(name)
    end
    line = record.value
    if line[:rules_kind] == :named && !@rule_sets.key?(line[:rules])
      return "unknown rule #{line[:rules]}"
    end
    if record.kind == :continuation && line[:until] && record.previous.field_error.nil?
      prior_limit = record.previous.value[:until]
      return 'until not increasing' if line[:until][:value] <= prior_limit[:value]
    end
    if line[:until] && @blocks[record.block][:records].last.equal?(record)
      return 'missing continuation'
    end
    nil
  end

  def define_database
    @records.each do |record|
      record.field_error = check_fields(record)
      record.error = record.field_error
    end
    @rule_sets = {}
    @records.each do |record|
      next unless record.kind == :rule && record.field_error.nil?

      (@rule_sets[record.fields[1]] ||= []) << record.value
    end
    seen = Set.new
    @records.each do |record|
      next unless %i[zone continuation].include?(record.kind) && record.field_error.nil?

      record.error = structural_error(record, seen)
    end
    @zones = {}
    @blocks.each do |block|
      next if block[:records].any?(&:error)

      @zones[block[:name]] = { name: block[:name], lines: block[:records].map(&:value), aliases: [],
                              periods: [], applied: Hash.new(0) }
    end
    @by_name = @zones.dup
    @records.each do |record|
      next unless record.kind == :link && record.error.nil?

      target_name, alias_name = record.fields.drop(1)
      target = @zones[target_name]
      if target.nil?
        record.error = "unknown link target #{target_name}"
      elsif @by_name.key?(alias_name)
        record.error = "duplicate link #{alias_name}"
      else
        @by_name[alias_name] = target
        target[:aliases] << alias_name
      end
    end
  end

  def assemble_periods
    sequences = @rule_sets.to_h { |name, rules| [name, Transitions.instances(rules)] }
    @zones.each_value do |zone|
      start = nil
      zone[:lines].each do |line|
        offset = line[:offset]
        limit = line[:until]
        if line[:rules_kind] == :named
          result = Transitions.process(sequences.fetch(line[:rules]), offset, start, limit)
        else
          save = line[:rules]
          finish = limit && limit[:value] - Transitions.adj(limit[:time][1], offset, save)
          result = { finish: finish, save: save, letter: '', applied: [] }
        end
        line[:start] = start
        line[:finish] = result[:finish]
        switches = [[start, result[:save], result[:letter]]]
        result[:applied].each do |instance|
          zone[:applied][instance[:rule_line]] += 1
          switches << [instance[:time], instance[:save], instance[:letter]]
        end
        switches.each do |time, save, letter|
          state = [offset + save, !save.zero?, Transitions.abbreviation(line[:format], save, letter)]
          previous = zone[:periods].last
          zone[:periods] << { start: time, state: state } if previous.nil? || previous[:state] != state
        end
        start = result[:finish]
      end
    end
  end

  def validate_arguments(arguments, kinds)
    values = []
    arguments.each_with_index do |word, index|
      kind = kinds[index]
      value = case kind
              when :zone then @by_name[word]
              when :year then TzParser.year(word)
              when :date then TzParser.date(word)
              when :local then TzParser.timestamp(word)
              when :ut then TzParser.timestamp(word, true)
              end
      if value.nil?
        reason = kind == :zone ? 'unknown zone' : 'invalid value'
        return [nil, "ERROR #{reason} #{word}"]
      end
      values << value
    end
    [values, nil]
  end

  def resolved_result(zone, local, choice)
    periods = zone[:periods]
    candidates = Resolver.candidates(periods, local)
    if candidates.empty?
      before, after = Resolver.skipping(periods, local)
      time = after[:start]
      first = Report.local(time + before[:state][0])
      last = Report.local(time + after[:state][0])
      return [nil, "NONEXISTENT gap #{first} to #{last} at #{Report.ut(time)}"]
    end
    if candidates.length == 2 && choice.nil?
      descriptions = candidates.map { |time, period| "#{Report.ut(time)} (#{Report.state(period[:state])})" }
      return [nil, "AMBIGUOUS #{descriptions.join(' or ')}"]
    end
    candidate = choice == 'LATER' ? candidates.last : candidates.first
    time, period = candidate
    [candidate, "#{Report.ut(time)} (#{Report.state(period[:state])})"]
  end

  def shifts(pairs)
    gaps = overlaps = same = 0
    pairs.each do |before, after|
      difference = after[:state][0] - before[:state][0]
      if difference.positive?
        gaps += 1
      elsif difference.negative?
        overlaps += 1
      else
        same += 1
      end
    end
    "gaps #{gaps}, overlaps #{overlaps}, no shift #{same}"
  end

  def transition_line(before, after)
    time = after[:start]
    difference = after[:state][0] - before[:state][0]
    kind = if difference.positive?
             "gap #{Report.duration(difference)}"
           elsif difference.negative?
             "overlap #{Report.duration(-difference)}"
           else
             'no shift'
           end
    "#{Report.change(before, after)} (local #{Report.local(time + before[:state][0])} -> " \
      "#{Report.local(time + after[:state][0])}, #{kind})"
  end

  def merge_intervals(intervals)
    merged = []
    intervals.sort_by(&:first).each do |first, last|
      if merged.empty? || first > merged.last[1]
        merged << [first, last]
      else
        merged.last[1] = [merged.last[1], last].max
      end
    end
    merged
  end

  def intersect_intervals(left, right)
    intersections = []
    i = j = 0
    while i < left.length && j < right.length
      first = [left[i][0], right[j][0]].max
      last = [left[i][1], right[j][1]].min
      intersections << [first, last] if first < last
      if left[i][1] <= right[j][1]
        i += 1
      else
        j += 1
      end
    end
    merge_intervals(intersections)
  end

  def working_hours(zone, date)
    intervals = []
    zone[:periods].each_with_index do |period, index|
      first, last = Resolver.range(zone[:periods], index)
      offset = period[:state][0]
      lower = [date * 86_400 + @workday[0] - offset, first].compact.max
      upper = [date * 86_400 + @workday[1] - offset, last].compact.min
      intervals << [lower, upper] if lower < upper
    end
    merge_intervals(intervals)
  end

  def meeting(date, zones, names)
    overlap = working_hours(zones.first, date)
    zones.drop(1).each { |zone| overlap = intersect_intervals(overlap, working_hours(zone, date)) }
    return 'NONE' if overlap.empty?

    overlap.map do |first, last|
      descriptions = zones.each_with_index.map do |zone, index|
        state = Resolver.period(zone[:periods], first)[:state]
        "#{names[index]} #{Report.local(first + state[0])} #{state[2]}"
      end
      "#{Report.ut(first)} to #{Report.ut(last)} (#{Report.duration(last - first)}) [#{descriptions.join(', ')}]"
    end.join('; ')
  end

  def duration_result(zone, locals, words)
    candidates = []
    locals.each_with_index do |local, index|
      resolved = Resolver.candidates(zone[:periods], local)
      return "NONEXISTENT #{words[index]}" if resolved.empty?
      return "AMBIGUOUS #{words[index]}" if resolved.length == 2

      candidates << resolved.first
    end
    elapsed = candidates[1][0] - candidates[0][0]
    offset_change = candidates[1][1][:state][0] - candidates[0][1][:state][0]
    "#{elapsed} s (#{Report.duration(elapsed)}), wall clock #{Report.duration(locals[1] - locals[0])}, " \
      "offset change #{Report.offset(offset_change)}"
  end

  def query_result(query)
    command, *arguments = query.split(' ')
    choice = nil
    if %w[TOUTC CONVERT].include?(command) && %w[EARLIER LATER].include?(arguments.last)
      choice = arguments.pop
    end
    kinds = command == 'MEETING' ? [:date] + Array.new(arguments.length - 1, :zone) : ARGUMENTS.fetch(command)
    values, error = validate_arguments(arguments, kinds)
    return error if error
    return 'ERROR invalid range' if command == 'TRANSITIONS' && values[1] > values[2]

    case command
    when 'TOUTC'
      resolved_result(values[0], values[1], choice)[1]
    when 'TOLOCAL'
      zone, time = values
      state = Resolver.period(zone[:periods], time)[:state]
      "#{Report.local(time + state[0])} (#{Report.state(state)})"
    when 'CONVERT'
      source, destination, local = values
      candidate, text = resolved_result(source, local, choice)
      return text if candidate.nil?

      time = candidate[0]
      state = Resolver.period(destination[:periods], time)[:state]
      shifted = time + state[0]
      difference = shifted.div(86_400) - local.div(86_400)
      shift = difference.positive? ? "+#{difference}" : difference.to_s
      "#{Report.local(shifted)} (#{Report.state(state)}) at #{Report.ut(time)}, day shift #{shift}"
    when 'OFFSET'
      zone, time = values
      periods = zone[:periods]
      index = Resolver.period_index(periods, time)
      text = Report.state(periods[index][:state])
      text += " since #{Report.ut(periods[index][:start])}" if index.positive?
      text += " until #{Report.ut(periods[index + 1][:start])}" if index + 1 < periods.length
      text
    when 'TRANSITIONS'
      zone, first_year, last_year = values
      first = DayRules.day_number(first_year, 1, 1) * 86_400
      last = DayRules.day_number(last_year + 1, 1, 1) * 86_400
      pairs = zone[:periods].each_cons(2).select { |_, after| after[:start] >= first && after[:start] < last }
      block = [query] + pairs.map { |before, after| transition_line(before, after) } + [shifts(pairs)]
      @transition_blocks << block
      "transitions: #{pairs.length}"
    when 'DURATION'
      duration_result(values[0], values.drop(1), arguments.drop(1))
    when 'MEETING'
      meeting(values[0], values.drop(1), arguments.drop(1))
    end
  end

  def rule_names(zone)
    zone[:lines].filter_map { |line| line[:rules] if line[:rules_kind] == :named }.uniq
  end

  def list_or_none(values, separator = ' ')
    values.empty? ? 'none' : values.join(separator)
  end

  def database_summary
    rules = @records.select { |record| record.kind == :rule }
    links = @records.select { |record| record.kind == :link }
    good_rules = rules.count { |record| record.error.nil? }
    good_links = links.count { |record| record.error.nil? }
    invalid = @blocks.select { |block| block[:records].any?(&:error) }
    zone_rules = @zones.values.map { |zone| rule_names(zone) }
    unused = @rule_sets.keys.reject { |name| zone_rules.any? { |names| names.include?(name) } }
    bad_names = invalid.map { |block| "#{block[:name]} (line #{block[:records].first.number})" }
    details = [
      "rule lines: #{good_rules} valid, #{rules.length - good_rules} invalid",
      "zones: #{@zones.length} defined, #{invalid.length} invalid",
      "zone lines: #{@zones.values.sum { |zone| zone[:lines].length }} in defined zones",
      "links: #{good_links} defined, #{links.length - good_links} invalid",
      "errors: #{@errors.length}", "unused rules: #{list_or_none(unused)}",
      "invalid zones: #{list_or_none(bad_names, ', ')}"
    ]
    @rule_sets.each do |name, set|
      first = set.map { |rule| rule[:from] }.min
      last = set.any? { |rule| rule[:raw][3] == 'max' } ? 'max' : set.map { |rule| rule[:to] }.max
      count = zone_rules.count { |names| names.include?(name) }
      details << "rule set #{name}: lines #{set.length}, years #{first}-#{last}, zones #{count}"
    end
    ['DATABASE'] + details.map { |line| "  #{line}" }
  end

  def in_line?(time, line)
    (line[:start].nil? || time >= line[:start]) && (line[:finish].nil? || time < line[:finish])
  end

  def zone_line_description(line, index, pairs)
    rules = case line[:rules_kind]
            when :none then '-'
            when :fixed then Report.clock(line[:rules])
            else line[:rules]
            end
    text = "line #{index + 1}: #{Report.offset(line[:offset])} #{rules} #{line[:format]}"
    text += " from #{Report.ut(line[:start])}" if index.positive?
    if line[:until]
      limit = line[:until]
      notation = limit[:raw].join(' ') + " #{Report.clock(limit[:time][0])}#{limit[:time][1]}"
      text += " until #{notation} = #{Report.ut(line[:finish])}"
    end
    text + ", transitions #{pairs.count { |_, after| in_line?(after[:start], line) }}"
  end

  def rule_description(name, rule, applied)
    raw = rule[:raw]
    "rule #{name} #{raw[2]} #{raw[3]} #{raw[5]} #{raw[6]} " \
      "#{Report.clock(rule[:at][0])}#{rule[:at][1]} #{Report.clock(rule[:save])} #{raw[9]}, applied #{applied}"
  end

  def dst_details(periods)
    selected = periods.each_with_index.select { |period, _| period[:state][1] }
    years = selected.map { |period, _| DayRules.parts(period[:start])[0] }
    details = [years.empty? ? 'dst years: none' : "dst years: #{years.min}-#{years.max}"]
    year = DayRules.parts(@reference)[0]
    year_start = DayRules.day_number(year, 1, 1) * 86_400
    year_end = DayRules.day_number(year + 1, 1, 1) * 86_400
    intervals = selected.filter_map do |_, index|
      first, last = Resolver.range(periods, index)
      lower = [first, year_start].compact.max
      upper = [last, year_end].compact.min
      [lower, upper] if lower < upper
    end
    intervals = merge_intervals(intervals)
    intervals.each do |first, last|
      details << "dst period: #{Report.ut(first)} to #{Report.ut(last)} (#{Report.duration(last - first)})"
    end
    total = intervals.sum { |first, last| last - first }
    details << "dst total #{year}: #{Report.duration(total)}"
    details
  end

  def zone_summary(zone)
    periods = zone[:periods]
    pairs = periods.each_cons(2).to_a
    details = ["aliases: #{list_or_none(zone[:aliases])}"]
    zone[:lines].each_with_index { |line, index| details << zone_line_description(line, index, pairs) }
    rule_names(zone).each do |name|
      @rule_sets.fetch(name).each do |rule|
        details << rule_description(name, rule, zone[:applied][rule[:line]])
      end
    end
    offsets = periods.map { |period| period[:state][0] }
    details << "offset range: #{Report.offset(offsets.min)} to #{Report.offset(offsets.max)}"
    states = {}
    periods.each do |period|
      state = period[:state]
      states[state] = states.fetch(state, 0) + 1
    end
    states.each { |state, count| details << "state #{Report.state(state)}, periods #{count}" }
    index = Resolver.period_index(periods, @reference)
    state = periods[index][:state]
    line_index = zone[:lines].index { |line| in_line?(@reference, line) }
    details << "reference: #{Report.local(@reference + state[0])} (#{Report.state(state)}), line #{line_index + 1}"
    previous = index.positive? ? Report.change(periods[index - 1], periods[index]) : 'none'
    following = index + 1 < periods.length ? Report.change(periods[index], periods[index + 1]) : 'none'
    details << "previous transition: #{previous}"
    details << "next transition: #{following}"
    details << "transitions: #{pairs.length}, #{shifts(pairs)}"
    details.concat(dst_details(periods))
    ["ZONE #{zone[:name]}"] + details.map { |line| "  #{line}" }
  end

  def run
    read_input
    define_database
    assemble_periods
    @errors = @records.filter_map { |record| "line #{record.number}: #{record.error}" if record.error }
    @transition_blocks = []
    answers = @queries.map { |query| "#{query} => #{query_result(query)}" }
    summaries = [database_summary] + @zones.keys.sort.map { |name| zone_summary(@zones.fetch(name)) }
    Dir.mkdir('output') unless Dir.exist?('output')
    Report.lines('output/answers.txt', answers)
    Report.blocks('output/transitions.txt', @transition_blocks)
    Report.blocks('output/zone_summary.txt', summaries)
    Report.lines('output/errors.txt', @errors)
  end
end

TimezoneEngine.new.run
