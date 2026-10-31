require_relative "numerics"

module GroupTests
  WEIGHTS = %w[logrank gehan_wilcoxon tarone_ware].freeze
  module_function

  def empty_totals(groups)
    size = groups.length
    { groups: groups.dup, events: Array.new(size, 0), observed: Array.new(size, 0.0),
      expected: Array.new(size, 0.0), covariance: Array.new(size) { Array.new(size, 0.0) } }
  end

  def weighted_totals(subjects, groups, weight, population_size)
    result = empty_totals(groups)
    collections = groups.map { |group| subjects.select { |subject| subject.group == group } }
    times = subjects.select { |subject| subject.event == 1 }.map(&:time).uniq.sort
    times.each do |time|
      risk = collections.map { |rows| rows.count { |subject| subject.time >= time } }
      deaths = collections.map { |rows| rows.count { |subject| subject.time == time && subject.event == 1 } }
      n, d = risk.sum, deaths.sum
      value = case weight
              when "logrank" then 1.0
              when "gehan_wilcoxon" then n.to_f / population_size
              else Math.sqrt(n.to_f / population_size)
              end
      groups.each_index do |h|
        result[:events][h] += deaths[h]
        result[:observed][h] += value * deaths[h]
        result[:expected][h] += value * ((d * risk[h]).to_f / n)
        next if n < 2

        factor = value * value * ((d * (n - d)).to_f / ((n - 1) * n * n))
        groups.each_index do |other|
          multiple = h == other ? risk[h] * (n - risk[h]) : -(risk[h] * risk[other])
          result[:covariance][h][other] += factor * multiple
        end
      end
    end
    result
  end

  def finish_test(result)
    degrees = result[:groups].length - 1
    difference = Array.new(degrees) { |h| result[:observed][h] - result[:expected][h] }
    matrix = result[:covariance].first(degrees).map { |row| row.first(degrees) }
    solution = Numerics.solve(matrix, difference)
    statistic = Numerics.total(difference.each_index.map { |h| difference[h] * solution[h] })
    result.merge(statistic: statistic, degrees: degrees, p: Numerics.chi_square_p(statistic, degrees))
  end

  def weighted_test(subjects, groups, weight, population_size)
    finish_test(weighted_totals(subjects, groups, weight, population_size))
  end

  def combine_strata(strata, groups)
    result = empty_totals(groups)
    strata.each do |stratum|
      groups.each_index do |h|
        result[:events][h] += stratum[:events][h]
        result[:observed][h] += stratum[:observed][h]
        result[:expected][h] += stratum[:expected][h]
        groups.each_index { |other| result[:covariance][h][other] += stratum[:covariance][h][other] }
      end
    end
    finish_test(result)
  end
end
