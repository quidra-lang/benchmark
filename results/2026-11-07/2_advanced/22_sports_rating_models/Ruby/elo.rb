# frozen_string_literal: true

module Elo
  Fit = Data.define(:ratings, :expected, :changes, :rounds)

  def self.expected(home_rating, away_rating, advantage)
    1.0 / (1.0 + 10.0**((away_rating - home_rating - advantage) / 400.0))
  end

  def self.fit(count, matches, coefficient, advantage, initial)
    ratings = Array.new(count, initial.to_f)
    expectations = []
    changes = []
    rounds = {}
    matches.each_with_index do |match, index|
      home = ratings[match.home]
      away = ratings[match.away]
      probability = expected(home, away, advantage)
      margin = (match.home_score - match.away_score).abs
      multiplier = 1.0
      if margin.positive?
        difference = match.result == 1 ? home + advantage - away : away - home - advantage
        multiplier = Math.log(margin + 1) * 2.2 / (0.001 * difference + 2.2)
      end
      change = coefficient * multiplier * (match.result.to_f - probability)
      ratings[match.home] = home + change
      ratings[match.away] = away - change
      expectations << probability
      changes << change
      if index + 1 == matches.length || matches[index + 1].round != match.round
        rounds[match.round] = ratings.dup
      end
    end
    Fit.new(ratings, expectations, changes, rounds)
  end
end
