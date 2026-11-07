func smallestMultiple(_ quantity: Int, _ multiple: Int) -> Int { (quantity + multiple - 1) / multiple * multiple }

func lotSize(_ item: Item, week: Int, projected: Int, receipts: [Int], gross: [Int], horizon: Int) -> Int {
    let net = item.safety - projected
    switch item.rule {
    case "LFL": return net
    case "FOQ": return smallestMultiple(net, item.parameters[0])
    case "MIN": return smallestMultiple(max(net, item.parameters[0]), item.parameters[1])
    default:
        var quantity = net
        var available = projected
        let end = min(week + item.parameters[0] - 1, horizon)
        if end > week {
            for later in (week + 1)...end {
                available += receipts[later] - gross[later]
                quantity = max(quantity, item.safety - available)
            }
        }
        return quantity
    }
}
