# frozen_string_literal: true

module Stats
  module_function

  def decimal(numerator, denominator, places)
    return '-' if denominator.zero?

    scale = 10**places
    rounded = (2 * numerator * scale + denominator).div(2 * denominator)
    "#{rounded.div(scale)}.#{(rounded % scale).to_s.rjust(places, '0')}"
  end

  def fraction(numerator, denominator)
    return '-' if denominator.zero?

    divisor = numerator.gcd(denominator)
    "#{numerator.div(divisor)}/#{denominator.div(divisor)}"
  end

  def percentile(sorted, percentage)
    sorted[(percentage * sorted.length + 99).div(100) - 1]
  end

  def travel_block(heading, times, width)
    return ["#{heading} exited 0"] if times.empty?

    sorted = times.sort
    line = "#{heading} exited #{sorted.length} min #{sorted.first} p50 #{percentile(sorted, 50)}"
    line += " p90 #{percentile(sorted, 90)} max #{sorted.last} mean #{decimal(sorted.sum, sorted.length, 2)}"
    lines = [line]
    counts = Hash.new(0)
    sorted.each { |time| counts[time.div(width)] += 1 }
    maximum = counts.values.max
    sorted.first.div(width).upto(sorted.last.div(width)) do |bin|
      count = counts[bin]
      stars = (80 * count + maximum).div(2 * maximum)
      row = "  #{bin * width}-#{bin * width + width - 1} #{count}"
      row += ' ' + '*' * stars if stars > 0
      lines << row
    end
    lines
  end
end
