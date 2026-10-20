module Cleaning
  module_function

  def median(values)
    sorted = values.sort
    middle = sorted.length / 2
    sorted.length.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
  end

  def flat_runs(numeric, minimum)
    runs = []
    start = 0
    while start < numeric.length
      last = start
      while last + 1 < numeric.length && numeric[last + 1][:time] == numeric[last][:time] + 1 && numeric[last + 1][:milli] == numeric[start][:milli]
        last += 1
      end
      runs << {start: numeric[start][:time], end: numeric[last][:time], value: numeric[start][:value]} if last - start + 1 >= minimum
      start = last + 1
    end
    runs
  end

  def spike_tests(candidates, settings)
    tested = 0
    spikes = []
    left = right = 0
    candidates.each do |row|
      right += 1 while right < candidates.length && candidates[right][:time] <= row[:time] + settings[:window]
      left += 1 while left < right && candidates[left][:time] < row[:time] - settings[:window]
      next if right - left < settings[:count]
      tested += 1
      values = candidates[left...right].map { |item| item[:preliminary] }
      center = median(values)
      deviation = median(values.map { |value| (value - center).abs })
      limit = [settings[:factor] * 1.4826 * deviation, settings[:minimum]].max
      if (row[:preliminary] - center).abs > limit
        spikes << {time: row[:time], value: row[:value], residual: row[:preliminary], median: center, mad: deviation, limit: limit}
      end
    end
    [tested, spikes]
  end

  def gaps(first, last, reasons)
    result = []
    time = first
    while time <= last
      unless reasons.key?(time)
        time += 1
        next
      end
      start = time
      cause = reasons[time]
      while time <= last && reasons.key?(time)
        cause = 'mixed' if reasons[time] != cause
        time += 1
      end
      result << {start: start, end: time - 1, cause: cause}
    end
    result
  end
end
