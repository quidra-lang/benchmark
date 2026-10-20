# frozen_string_literal: true

module Capability
  module_function

  def interval(value, count, coefficient)
    delta = coefficient * Math.sqrt(1.0 / (9 * count).to_f + value * value / (2 * (count - 1)).to_f)
    [value - delta, value + delta]
  end

  def calculate(subgroups, samples, settings, constants)
    values = samples.map(&:last)
    count = values.length
    mean = values.sum.to_f / count.to_f
    range = subgroups.sum(&:range).to_f / subgroups.length.to_f
    deviation_sum = 0.0
    subgroups.each { |subgroup| deviation_sum += subgroup.sd }
    average_sd = deviation_sum / subgroups.length.to_f
    within = range / constants[:d2]
    sbar = average_sd / constants[:c4]
    squares = 0.0
    values.each do |value|
      difference = value - mean
      squares += difference * difference
    end
    overall = Math.sqrt(squares / (count - 1))
    lower = settings['lsl']
    upper = settings['usl']
    width = upper - lower
    cp = width / (6 * within)
    cpu = (upper - mean) / (3 * within)
    cpl = (mean - lower) / (3 * within)
    cpk = [cpu, cpl].min
    pp = width / (6 * overall)
    ppu = (upper - mean) / (3 * overall)
    ppl = (mean - lower) / (3 * overall)
    ppk = [ppu, ppl].min
    offset = mean - settings['target']
    cpm = width / (6 * Math.sqrt(overall * overall + offset * offset))
    below = values.count { |value| value < lower }
    above = values.count { |value| value > upper }
    verdict = cpk >= 1.33 ? 'capable' : cpk >= 1.00 ? 'marginal' : 'incapable'
    {mean: mean, sigma_within: within, sigma_sbar: sbar, sigma_overall: overall,
     cp: cp, cpu: cpu, cpl: cpl, cpk: cpk, pp: pp, ppu: ppu, ppl: ppl, ppk: ppk, cpm: cpm,
     cpk_ci: interval(cpk, count, settings['ci_z']), ppk_ci: interval(ppk, count, settings['ci_z']),
     below_lsl: below, above_usl: above, ppm: (1_000_000 * (below + above)).to_f / count.to_f, verdict: verdict}
  end

  def histogram(samples, settings)
    values = samples.map(&:last)
    width = settings['histogram_bin']
    lower = width * ([values.min, settings['lsl']].min.to_f / width.to_f).floor
    upper = width * ([values.max, settings['usl']].max.to_f / width.to_f).floor + width
    counts = Array.new((upper - lower) / width, 0)
    values.each { |value| counts[(value - lower) / width] += 1 }
    top = counts.max
    counts.each_with_index.map do |count, index|
      start = lower + index * width
      finish = start + width - 1
      marks = %w[lsl target usl].select { |name| settings[name].between?(start, finish) }
      {start: start, finish: finish, count: count, bar: (50 * count + top - 1) / top, marks: marks}
    end
  end
end
