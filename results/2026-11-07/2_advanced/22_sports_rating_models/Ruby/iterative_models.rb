# frozen_string_literal: true

module IterativeModels
  def self.bradley_terry(count, matches, iterations)
    wins = Array.new(count, 0.0)
    home_wins = 0.0
    matches.each do |match|
      result = match.result.to_f
      wins[match.home] += result
      wins[match.away] += 1.0 - result
      home_wins += result
    end
    strengths = Array.new(count, 1.0)
    theta = 1.0
    iterations.times do
      denominators = Array.new(count, 0.0)
      matches.each do |match|
        divisor = theta * strengths[match.home] + strengths[match.away]
        denominators[match.home] += theta / divisor
        denominators[match.away] += 1.0 / divisor
      end
      strengths = Array.new(count) { |index| wins[index] / denominators[index] }
      total = 0.0
      strengths.each { |value| total += value }
      strengths.map! { |value| value * count / total }
      denominator = 0.0
      matches.each do |match|
        denominator += strengths[match.home] / (theta * strengths[match.home] + strengths[match.away])
      end
      theta = home_wins / denominator
    end
    [strengths, theta]
  end

  def self.offense_defense(count, matches, iterations)
    points = Array.new(count) { Array.new(count, 0) }
    matches.each do |match|
      points[match.away][match.home] += match.home_score
      points[match.home][match.away] += match.away_score
    end
    defense = Array.new(count, 1.0)
    offense = Array.new(count, 0.0)
    iterations.times do
      count.times do |team|
        total = 0.0
        count.times { |opponent| total += points[opponent][team] / defense[opponent] }
        offense[team] = total
      end
      count.times do |team|
        total = 0.0
        count.times { |opponent| total += points[team][opponent] / offense[opponent] }
        defense[team] = total
      end
    end
    rating = Array.new(count) { |team| offense[team] / defense[team] }
    [offense, defense, rating]
  end
end
