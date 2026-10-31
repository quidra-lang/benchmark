require_relative 'low_level'

module Prioritized
  def self.try_order(grid, agents, distances, horizon, order, budget)
    restrictions, paths, attempts = LowLevel::Prohibitions.new, {}, []
    order.each do |id|
      begin
        path, expansions = LowLevel.search(grid, agents[id], distances[id], agents[id].start,
                                           0, restrictions, horizon, budget)
      rescue LowLevel::BudgetExceeded
        return [nil, attempts, 'll_budget']
      end
      attempts << { agent: id, path: path, expansions: expansions }
      return [nil, attempts, id] unless path

      paths[id] = path
      restrictions.reserve(path, forever: true)
    end
    [agents.each_index.map { |id| paths.fetch(id) }, attempts, nil]
  end
end
