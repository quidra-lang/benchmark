smallest_multiple =: 4 : 'y*(x+y-1) div y'
lot_size =: 4 : 0
    'week projected receipts gross' =. y
    safety =. 'safety_stock' get_key x
    net =. safety-projected
    rule =. 'rule' get_key x
    values =. 'lot' get_key x
    if. rule-:'LFL' do. net return. end.
    if. rule-:'FOQ' do. net smallest_multiple {.values return. end.
    if. rule-:'MIN' do. (net>.0{values) smallest_multiple 1{values return. end.
    quantity =. net
    finish =. Horizon<.week+{.values
    for_later. (week+1)+i.0>.finish-(week+1) do.
        projected =. projected+(later{receipts)-later{gross
        quantity =. quantity>.safety-projected
    end.
    quantity
)
