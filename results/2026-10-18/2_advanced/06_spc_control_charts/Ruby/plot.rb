# frozen_string_literal: true

module Plot
  module_function

  def put(band, position, character)
    band[[[position, 0].max, 60].min] = character
  end

  def position(value, limits)
    fraction = (value - limits.lcl) / (limits.ucl - limits.lcl)
    (60 * fraction + 0.5).floor
  end

  def shewhart(value, limits, signalled)
    band = Array.new(61, '.')
    put(band, 0, ':')
    put(band, 60, ':')
    put(band, position(limits.cl, limits), '|')
    put(band, position(value, limits), signalled ? '*' : 'o')
    band.join
  end

  def cusum(upper, lower, threshold, upper_signal, lower_signal)
    band = Array.new(61, '.')
    put(band, 0, ':')
    put(band, 60, ':')
    put(band, 30, '|')
    if lower > 0
      offset = [30, (30 * (lower / threshold) + 0.5).floor].min
      put(band, 30 - offset, lower_signal ? '*' : '-')
    end
    if upper > 0
      offset = [30, (30 * (upper / threshold) + 0.5).floor].min
      put(band, 30 + offset, upper_signal ? '*' : '+')
    end
    band.join
  end

  def smooth(value, target, width, current_width, signalled)
    band = Array.new(61, '.')
    extent = [30, (30 * (current_width / width) + 0.5).floor].min
    put(band, 30, '|')
    put(band, 30 - extent, ':')
    put(band, 30 + extent, ':')
    distance = (value - target) / width
    put(band, 30 + (30 * distance + 0.5).floor, signalled ? '*' : 'o')
    band.join
  end

  def standardized(value, status)
    band = Array.new(61, '.')
    put(band, 0, ':')
    put(band, 60, ':')
    put(band, 30, '|')
    put(band, 30 + (10 * value + 0.5).floor, status == 'ok' ? 'o' : '*')
    band.join
  end
end
