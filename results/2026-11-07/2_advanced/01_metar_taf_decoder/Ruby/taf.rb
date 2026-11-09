require_relative 'units'

module Taf
  SLOTS = [[:wind, false], [:visibility, false], [:weather, true], [:cloud, true]].freeze
  ELEMENTS = %i[wind visibility weather cloud].freeze

  module_function

  def indicator?(text)
    %w[BECMG TEMPO PROB30 PROB40].include?(text) || /\AFM\d{6}\z/.match?(text)
  end

  def split(groups, report, calendar)
    first = groups.index { |group| indicator?(group[:text]) } || groups.length
    base = groups.take(first)
    changes = []
    index = first
    while index < groups.length
      indicator = groups[index]
      kind = indicator[:text]
      index += 1
      if %w[PROB30 PROB40].include?(kind) && groups[index] && groups[index][:text] == 'TEMPO'
        kind += ' TEMPO'
        index += 1
      end
      finish = index
      finish += 1 while finish < groups.length && !indicator?(groups[finish][:text])
      content = groups[index...finish]
      change = nil
      if kind.start_with?('FM')
        day, hour, minute = [kind[2, 2], kind[4, 2], kind[6, 2]].map(&:to_i)
        time = hour <= 23 && minute <= 59 ? calendar.day_time(day, hour, minute, report[:issue_day]) : nil
        if time && report[:start] <= time && time < report[:end]
          change = {kind: 'FM', time:, groups: content}
        else
          yield indicator, 'invalid period'
        end
      elsif content.empty? || !/\A\d{4}\/\d{4}\z/.match?(content[0][:text])
        yield({text: kind, position: indicator[:position]}, 'missing period')
      else
        period = calendar.period(content[0][:text], report[:issue_day])
        if period && report[:start] <= period[0] && period[1] <= report[:end]
          change = {kind:, start: period[0], end: period[1], groups: content.drop(1)}
        else
          yield content[0], 'invalid period'
        end
      end
      changes << change if change
      index = finish
    end
    {base:, changes:}
  end

  def overlay(state, replacement, complete = false)
    ELEMENTS.to_h { |element| [element, complete || !replacement[element].nil? ? replacement[element] : state[element]] }
  end

  def expand(report)
    hours = {}
    (report[:start]...report[:end]).step(60) do |hour|
      state = ELEMENTS.to_h { |element| [element, report[:base][element]] }
      report[:changes].each do |change|
        if change[:kind] == 'FM' && change[:time] <= hour
          state = overlay(state, change[:state], true)
        elsif change[:kind] == 'BECMG' && change[:end] <= hour
          state = overlay(state, change[:state])
        end
      end
      yield state
      temporary = []
      report[:changes].each do |change|
        next if %w[FM BECMG].include?(change[:kind])
        next unless change[:start] <= hour && hour < change[:end]
        altered = overlay(state, change[:state])
        yield altered
        temporary << {kind: change[:kind], state: altered}
      end
      hours[hour] = {state:, temporary:}
    end
    hours
  end
end
