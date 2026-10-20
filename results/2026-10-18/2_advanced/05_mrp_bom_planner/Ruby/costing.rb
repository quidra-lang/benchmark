module Costing
  Cost = Struct.new(:material, :labor, :total, :usage, :value, :classification, keyword_init: true)

  def self.rollup(items, bom, plan)
    costs = {}
    bom.order.reverse_each do |id|
      material = items[id].material
      labor = items[id].labor
      bom.children[id].each do |row|
        factor = row.quantity * (100 + row.scrap)
        material += (2 * factor * costs[row.child].material + 100).div(200)
        labor += (2 * factor * costs[row.child].labor + 100).div(200)
      end
      total = material + labor
      usage = plan[:items][id][:gross].sum
      costs[id] = Cost.new(material: material, labor: labor, total: total, usage: usage, value: usage * total)
    end
    total_value = costs.values.sum(&:value)
    previous = 0
    costs.keys.sort_by { |id| [-costs[id].value, id] }.each do |id|
      cost = costs[id]
      cost.classification = if cost.value.zero?
                              'C'
                            elsif 100 * previous < 80 * total_value
                              'A'
                            elsif 100 * previous < 95 * total_value
                              'B'
                            else
                              'C'
                            end
      previous += cost.value
    end
    costs
  end
end
