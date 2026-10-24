module LotSizing
  module_function

  def size(item, net, balance, week, receipts, gross, horizon)
    case item.rule
    when 'LFL'
      net
    when 'FOQ'
      fixed = item.lot[0]
      (net + fixed - 1).div(fixed) * fixed
    when 'MIN'
      minimum, multiple = item.lot
      ([net, minimum].max + multiple - 1).div(multiple) * multiple
    when 'POQ'
      quantity = net
      (week + 1).upto([week + item.lot[0] - 1, horizon].min) do |future|
        balance += receipts[future] - gross[future]
        quantity = [quantity, item.safety - balance].max
      end
      quantity
    end
  end
end
