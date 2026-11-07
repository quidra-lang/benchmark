# frozen_string_literal: true

require_relative 'features'

module Profiles
  def self.rules(path)
    File.readlines(path, chomp: true).map do |line|
      name, *words = line.split(' ')
      conditions = words.each_slice(3).map { |feature, comparison, threshold| [Features::NAMES.index(feature), comparison, threshold.to_f] }
      { name: name, conditions: conditions }
    end
  end

  def self.match_rule(center, rules)
    rules.index do |rule|
      rule[:conditions].all? do |feature, comparison, threshold|
        comparison == '>' ? center[feature] > threshold : center[feature] < threshold
      end
    end
  end

  def self.original(center, means, deviations)
    center.each_index.map do |feature|
      value = means[feature] + deviations[feature] * center[feature]
      Features::SQUARE_ROOT.include?(feature) ? value * value : value
    end
  end
end
