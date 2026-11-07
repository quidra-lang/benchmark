require_relative 'tiles'

module Shanten
  @patterns = {}
  @numbers = {}

  def self.patterns(counts, suited)
    key = [counts, suited]
    return @patterns[key] if @patterns.key?(key)

    first = counts.index { |n| n.positive? }
    return [[0, 0, 0]] unless first

    choices = [[[first], 0, 0, 0]]
    choices << [[first] * 3, 1, 0, 0] if counts[first] >= 3
    if counts[first] >= 2
      choices << [[first] * 2, 0, 1, 0]
      choices << [[first] * 2, 0, 0, 1]
    end
    if suited
      if first <= 6 && counts[first + 1].positive? && counts[first + 2].positive?
        choices << [[first, first + 1, first + 2], 1, 0, 0]
      end
      [1, 2].each do |difference|
        other = first + difference
        choices << [[first, other], 0, 1, 0] if other < 9 && counts[other].positive?
      end
    end
    best = {}
    choices.each do |removed, em, et, eh|
      rest = counts.dup
      removed.each { |k| rest[k] -= 1 }
      patterns(rest, suited).each do |m, t, h|
        m += em
        h += eh
        next if m > 4 || h > 1

        t = [4, t + et].min
        state = [m, h]
        best[state] = [best.fetch(state, -1), t].max
      end
    end
    result = best.map { |(m, h), t| [m, t, h] }
    @patterns.clear if @patterns.size >= 65_536
    @patterns[key] = result
  end

  def self.standard(counts)
    states = { [0, 0] => 0 }
    [[0, 9], [9, 9], [18, 9], [27, 7]].each do |start, length|
      local = patterns(counts.slice(start, length), start < 27)
      combined = {}
      states.each do |(m, h), t|
        local.each do |lm, lt, lh|
          nm, nh = m + lm, h + lh
          next if nm > 4 || nh > 1

          state = [nm, nh]
          nt = [4, t + lt].min
          combined[state] = [combined.fetch(state, -1), nt].max
        end
      end
      states = combined
    end
    states.map { |(m, h), t| 8 - 2 * m - [t, 4 - m].min - h }.min
  end

  def self.numbers(counts)
    return @numbers[counts] if @numbers.key?(counts)

    seven = 6 - counts.count { |n| n >= 2 } + [0, 7 - counts.count(&:positive?)].max
    orphans = 13 - Tiles::YAOCHUU.count { |k| counts[k].positive? }
    orphans -= 1 if Tiles::YAOCHUU.any? { |k| counts[k] >= 2 }
    result = [standard(counts), seven, orphans]
    @numbers.clear if @numbers.size >= 8192
    @numbers[counts.dup] = result
  end
end
