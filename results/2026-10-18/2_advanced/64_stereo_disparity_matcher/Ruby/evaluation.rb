require_relative 'refinement'

module Evaluation
  REGION_ORDER = %w[nonocc all disc].freeze
  module_function

  def truth_regions(truth, width, height)
    known = truth.each_index.select { |p| truth[p] != 0 }
    occluded = known.select do |p|
      y, x = p.divmod(width)
      g = truth[p]
      x < g || width.times.any? do |xx|
        other = truth[y * width + xx]
        other > g && xx - other == x - g
      end
    end
    hidden = occluded.to_h { |p| [p, true] }
    visible = known.reject { |p| hidden[p] }
    disc = visible.select do |p|
      y, x = p.divmod(width)
      ([y - 1, 0].max..[y + 1, height - 1].min).any? do |yy|
        ([x - 1, 0].max..[x + 1, width - 1].min).any? do |xx|
          q = yy * width + xx
          truth[q] != 0 && (truth[q] - truth[p]).abs >= 2
        end
      end
    end
    { 'all' => known, 'nonocc' => visible, 'disc' => disc, 'occluded' => occluded }
  end

  def evaluate(image, truth, region)
    errors = region.filter_map { |p| (image[p] - truth[p]).abs if image[p] != 0 }
    valid = errors.length
    total = errors.sum
    missing = region.length - valid
    { pixels: region.length, valid: valid, bad1: missing + errors.count { |e| e > 1 },
      bad2: missing + errors.count { |e| e > 2 }, error_sum: total,
      mae: valid.positive? ? Refinement.two_decimals(total, valid) : '-', exact: errors.count(0) }
  end

  def ratio(numerator, denominator)
    return '0/1 0.00' if denominator.zero?
    divisor = numerator.gcd(denominator)
    "#{numerator / divisor}/#{denominator / divisor} #{Refinement.two_decimals(100 * numerator, denominator)}"
  end
end
