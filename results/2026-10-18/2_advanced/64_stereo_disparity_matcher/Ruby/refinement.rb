module Refinement
  module_function

  def hundredths(value)
    format('%d.%02d', value / 100, value % 100)
  end

  def two_decimals(numerator, denominator = 1)
    hundredths((200 * numerator + denominator) / (2 * denominator))
  end

  def depth_hundredths(disparity, focal, baseline)
    (200 * focal * baseline + disparity) / (2 * disparity)
  end

  def subpixel(disparity, costs, minimum, maximum, focal, baseline)
    index = disparity - minimum
    a, b = 0, 1
    if disparity > minimum && disparity < maximum && costs[index - 1] > costs[index] && costs[index + 1] >= costs[index]
      a = costs[index - 1] - costs[index + 1]
      b = 2 * (costs[index - 1] - 2 * costs[index] + costs[index + 1])
    end
    q = (200 * (disparity * b + a) + b) / (2 * b)
    [hundredths(q), two_decimals(100 * focal * baseline, q)]
  end
end
