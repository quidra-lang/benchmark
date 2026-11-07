module LotSizing

multiple(quantity, factor) = (quantity + factor - 1) ÷ factor * factor

function quantity(item, week, projected, receipts, gross, horizon)
    net = item.safety - projected
    item.rule == "LFL" && return net
    item.rule == "FOQ" && return multiple(net, item.first)
    item.rule == "MIN" && return multiple(max(net, item.first), item.second)
    result = net
    for later in week + 1:min(week + item.first - 1, horizon)
        projected += receipts[later] - gross[later]
        result = max(result, item.safety - projected)
    end
    return result
end

end
