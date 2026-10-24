# frozen_string_literal: true

module Season
  Team = Data.define(:id, :name)
  Match = Data.define(:round, :home, :away, :home_score, :away_score, :result, :line)

  def self.result(home_score, away_score)
    Rational((home_score <=> away_score) + 1, 2)
  end

  def self.read
    teams = File.readlines('input/teams.csv', chomp: true).drop(1).map do |line|
      Team.new(*line.split(','))
    end
    indices = teams.each_with_index.to_h { |team, index| [team.id, index] }
    matches = File.readlines('input/matches.csv', chomp: true).drop(1).each_with_index.map do |line, index|
      round, home, away, home_score, away_score = line.split(',')
      home_score = home_score.to_i
      away_score = away_score.to_i
      Match.new(round.to_i, indices.fetch(home), indices.fetch(away), home_score, away_score,
                result(home_score, away_score), index)
    end
    matches.sort_by! { |match| [match.round, match.line] }
    settings = {}
    File.readlines('input/params.txt', chomp: true).each do |line|
      keyword, *values = line.split(' ')
      key = keyword.downcase.to_sym
      settings[key] = case key
                      when :pythagorean_exponent then values.first.to_f
                      when :elo_grid_k, :elo_grid_home then values.map(&:to_i)
                      else values.first.to_i
                      end
    end
    [teams, matches, settings]
  end

  def self.before(matches, round)
    matches.take_while { |match| match.round < round }
  end
end
