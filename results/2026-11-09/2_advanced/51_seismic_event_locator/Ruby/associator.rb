require 'set'

module Associator
  module_function

  def associate(picks, window, minimum)
    candidates = []
    picks.each_with_index do |first, index|
      next if first[:assigned]
      selected = []
      stations = Set.new
      picks.drop(index).each do |pick|
        break if pick[:sample] > first[:sample] + window
        next if pick[:assigned] || !stations.add?(pick[:station][:order])
        selected << pick
      end
      next if selected.length < minimum
      selected.each { |pick| pick[:assigned] = true }
      candidates << {number: candidates.length + 1, first: first, picks: selected,
                     passes: [], dropped: [], rejected: false, event: nil}
    end
    candidates
  end
end
