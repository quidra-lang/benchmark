# frozen_string_literal: true

require_relative 'day_rules'

module Transitions
  def self.instances(rules)
    rules.flat_map do |rule|
      (rule[:from]..rule[:to]).map do |year|
        { nominal: DayRules.specification(year, rule[:month], rule[:day]) * 86_400 + rule[:at][0],
          type: rule[:at][1], save: rule[:save], letter: rule[:letter], rule_line: rule[:line] }
      end
    end.sort_by { |instance| [instance[:nominal], instance[:rule_line]] }
  end

  def self.adj(type, offset, save)
    return 0 if type == 'u'
    return offset if type == 's'

    offset + save
  end

  def self.process(sequence, offset, start, limit)
    current = 0
    starting_save = 0
    starting_letter = sequence.find { |instance| instance[:save].zero? }&.fetch(:letter) || ''
    applied = []
    sequence.each do |instance|
      time = instance[:nominal] - adj(instance[:type], offset, current)
      break if limit && time >= limit[:value] - adj(limit[:time][1], offset, current)

      if !start.nil? && time <= start
        starting_save = instance[:save]
        starting_letter = instance[:letter]
      else
        applied << { time: time, save: instance[:save], letter: instance[:letter], rule_line: instance[:rule_line] }
      end
      current = instance[:save]
    end
    finish = limit && limit[:value] - adj(limit[:time][1], offset, current)
    { finish: finish, save: starting_save, letter: starting_letter, applied: applied }
  end

  def self.abbreviation(format, save, letter)
    return format.split('/', -1)[save.zero? ? 0 : 1] if format.include?('/')

    format.gsub('%s', letter)
  end
end
