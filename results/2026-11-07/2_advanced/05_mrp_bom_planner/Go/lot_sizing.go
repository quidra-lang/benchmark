package main

func lotSize(item *Item,week int,projected int64,receipts,gross *[27]int64,horizon int) int64 {
    net:=item.Safety-projected
    switch item.Rule {
    case "LFL": return net
    case "FOQ": return (net+item.A-1)/item.A*item.A
    case "MIN": return (max(net,item.A)+item.B-1)/item.B*item.B
    }
    quantity:=net
    for later:=week+1;later<=min(week+int(item.A)-1,horizon);later++ { projected+=receipts[later]-gross[later]; quantity=max(quantity,item.Safety-projected) }
    return quantity
}
