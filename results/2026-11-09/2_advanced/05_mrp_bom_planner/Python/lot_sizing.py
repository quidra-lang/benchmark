def smallest_multiple(quantity, factor):
    return (quantity + factor - 1) // factor * factor


def lot_size(item, week, projected, receipts, gross, horizon):
    net = item.safety_stock - projected
    if item.rule == "LFL":
        return net
    if item.rule == "FOQ":
        return smallest_multiple(net, item.fixed_quantity)
    if item.rule == "MIN":
        return smallest_multiple(max(net, item.minimum), item.multiple)
    quantity = net
    for later in range(week + 1, min(week + item.periods - 1, horizon) + 1):
        projected += receipts[later] - gross[later]
        quantity = max(quantity, item.safety_stock - projected)
    return quantity
