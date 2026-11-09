module Eventlog
  MONTH_LENGTHS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31].freeze
  module_function

  def read_inputs
    rows = File.readlines('input/eventlog.csv', chomp: true).drop(1).each_with_index.map do |line, index|
      case_id, activity, timestamp, resource = line.split(',')
      {case_id: case_id, activity: activity, timestamp: timestamp, resource: resource, line: index + 2}
    end
    parameters = File.readlines('input/params.txt', chomp: true).to_h { |line| line.split }
    [rows, parameters]
  end

  def timestamp_minutes(timestamp)
    month, day, hour, minute = [timestamp[5, 2], timestamp[8, 2], timestamp[11, 2], timestamp[14, 2]].map(&:to_i)
    return nil unless month.between?(1, 12) && day.between?(1, MONTH_LENGTHS[month - 1]) && hour.between?(0, 23) && minute.between?(0, 59)
    days = MONTH_LENGTHS.take(month - 1).sum
    ((days + day - 1) * 24 + hour) * 60 + minute
  end

  def build_cases(events)
    events.group_by { |event| event[:case_id] }.sort.map do |id, group|
      ordered = group.sort_by { |event| [event[:time], event[:line]] }
      {id: id, events: ordered, trace: ordered.map { |event| event[:activity] }, duration: ordered.last[:time] - ordered.first[:time]}
    end
  end

  def median(values)
    sorted = values.sort
    middle = sorted.length / 2
    sorted.length.odd? ? Rational(sorted[middle]) : Rational(sorted[middle - 1] + sorted[middle], 2)
  end
end
