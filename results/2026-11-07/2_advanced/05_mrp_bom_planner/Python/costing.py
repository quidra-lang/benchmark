class StandardCost:
    def __init__(self, material, labor):
        self.material = material
        self.labor = labor
        self.total = material + labor


def component_cost(row, cost):
    return (row.qty_per * (100 + row.scrap) * cost + 50) // 100


def standard_costs(items, bom, planning_order):
    costs = {}
    for item_id in reversed(planning_order):
        item = items[item_id]
        material = item.material
        labor = item.labor
        for row in bom.children[item_id]:
            child = costs[row.child]
            material += component_cost(row, child.material)
            labor += component_cost(row, child.labor)
        costs[item_id] = StandardCost(material, labor)
    return costs


def abc_classes(values):
    ranked = sorted(values, key=lambda item_id: (-values[item_id], item_id))
    total = sum(values.values())
    classes = {}
    before = 0
    for item_id in ranked:
        value = values[item_id]
        if value == 0:
            classes[item_id] = "C"
        elif 100 * before < 80 * total:
            classes[item_id] = "A"
        elif 100 * before < 95 * total:
            classes[item_id] = "B"
        else:
            classes[item_id] = "C"
        before += value
    return classes
