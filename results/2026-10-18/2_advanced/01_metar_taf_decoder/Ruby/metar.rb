require_relative 'groups'

module Metar
  SLOTS = [[:modifier, false], [:wind, false], [:variation, false], [:visibility, false],
           [:rvr, true], [:weather, true], [:cloud, true], [:temperature, false],
           [:pressure, false], [:nosig, false]].freeze

  module_function

  def slot_value(kind, text) = Groups.recognize(kind, text)

  def time_group(group)
    match = /\A(FM|TL|AT)(\d{2})(\d{2})\z/.match(group[:text])
    {kind: match[1], hour: match[2].to_i, minute: match[3].to_i, group:} if match
  end

  def split(groups)
    remarks_at = groups.index { |group| group[:text] == 'RMK' } || groups.length
    before = groups.take(remarks_at)
    remarks = groups.drop(remarks_at + 1)
    trend_at = before.index { |group| %w[BECMG TEMPO].include?(group[:text]) } || before.length
    main = before.take(trend_at)
    trends = []
    index = trend_at
    while index < before.length
      indicator = before[index]
      finish = index + 1
      finish += 1 while finish < before.length && !%w[BECMG TEMPO].include?(before[finish][:text])
      content = before[(index + 1)...finish]
      times = []
      first = content[0] && time_group(content[0])
      if first
        times << first
        content = content.drop(1)
        second = content[0] && time_group(content[0])
        if first[:kind] == 'FM' && second && second[:kind] == 'TL'
          times << second
          content = content.drop(1)
        end
      end
      invalid = times.find { |time| time[:hour] > 23 || time[:minute] > 59 }
      if invalid
        yield invalid[:group], 'invalid period'
      else
        trends << {kind: indicator[:text], times:, groups: content}
      end
      index = finish
    end
    {main:, trends:, remarks: read_remarks(remarks)}
  end

  def read_remarks(groups)
    sea_levels = []
    temperatures = []
    groups.each do |group|
      if (match = /\ASLP(\d{3})\z/.match(group[:text]))
        value = match[1].to_i
        sea_levels << (value >= 500 ? 9000 : 10_000) + value
      elsif (match = /\AT([01])(\d{3})([01])(\d{3})\z/.match(group[:text]))
        temperatures << [match[2].to_i * (match[1] == '1' ? -1 : 1),
                         match[4].to_i * (match[3] == '1' ? -1 : 1)]
      end
    end
    {sea_levels:, temperatures:}
  end
end
