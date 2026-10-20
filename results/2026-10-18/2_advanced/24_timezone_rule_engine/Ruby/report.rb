# frozen_string_literal: true

require_relative 'day_rules'

module Report
  def self.local(value)
    format('%04d-%02d-%02dT%02d:%02d:%02d', *DayRules.parts(value))
  end

  def self.ut(value)
    local(value) + 'Z'
  end

  def self.offset(value)
    hour, remainder = value.abs.divmod(3600)
    minute, second = remainder.divmod(60)
    text = format('%s%02d:%02d', value.negative? ? '-' : '+', hour, minute)
    second.zero? ? text : text + format(':%02d', second)
  end

  def self.duration(value)
    hour, remainder = value.abs.divmod(3600)
    minute, second = remainder.divmod(60)
    format('%s%d:%02d:%02d', value.negative? ? '-' : '', hour, minute, second)
  end

  def self.clock(value)
    hour, remainder = value.divmod(3600)
    minute, second = remainder.divmod(60)
    text = format('%d:%02d', hour, minute)
    second.zero? ? text : text + format(':%02d', second)
  end

  def self.state(state)
    "#{offset(state[0])} #{state[1] ? 'DST' : 'STD'} #{state[2]}"
  end

  def self.change(before, after)
    "#{ut(after[:start])} #{state(before[:state])} -> #{state(after[:state])}"
  end

  def self.lines(path, lines)
    File.binwrite(path, lines.empty? ? '' : lines.join("\n") + "\n")
  end

  def self.blocks(path, blocks)
    text = blocks.map { |block| block.join("\n") }.join("\n\n")
    File.binwrite(path, blocks.empty? ? '' : text + "\n")
  end
end
