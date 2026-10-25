struct StandardCost { let material: Int; let labor: Int; var total: Int { material + labor } }

func standardCosts(items: [String: Item], bom: Bom, order: [String]) -> [String: StandardCost] {
    var costs: [String: StandardCost] = [:]
    for id in order.reversed() {
        var material = items[id]!.material
        var labor = items[id]!.labor
        for row in bom.children[id]! {
            let child = costs[row.child]!
            material += (row.quantity * (100 + row.scrap) * child.material + 50) / 100
            labor += (row.quantity * (100 + row.scrap) * child.labor + 50) / 100
        }
        costs[id] = StandardCost(material: material, labor: labor)
    }
    return costs
}

func abcClasses(_ values: [String: Int]) -> [String: String] {
    let total = values.values.reduce(0, +)
    let ranked = values.keys.sorted { values[$0]! == values[$1]! ? $0 < $1 : values[$0]! > values[$1]! }
    var classes: [String: String] = [:]
    var before = 0
    for id in ranked {
        let value = values[id]!
        classes[id] = value == 0 ? "C" : 100 * before < 80 * total ? "A" : 100 * before < 95 * total ? "B" : "C"
        before += value
    }
    return classes
}
