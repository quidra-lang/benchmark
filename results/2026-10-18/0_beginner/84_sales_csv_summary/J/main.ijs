split =: 4 : 0
  <;._1 x,y
)

main =: 3 : 0
  csv =. 'date,region,product,quantity,unit_price';'2026-04-01,north,notebook,10,200';'2026-04-01,east,marker,6,150';'2026-04-01,south,eraser,25,80';'2026-04-02,west,stapler,4,600';'2026-04-02,north,marker,8,150';'2026-04-02,east,notebook,9,200';'2026-04-03,south,stapler,3,600';'2026-04-03,west,eraser,15,80';'2026-04-03,north,eraser,20,80';'2026-04-04,east,stapler,5,600';'2026-04-04,south,notebook,6,200';'2026-04-04,west,marker,8,150'
  dates =. regions =. products =. 0$<''
  quantities =. amounts =. i.0
  for_line. }.csv do.
    fields =. ',' split >line
    dates =. dates,0{fields
    regions =. regions,1{fields
    products =. products,2{fields
    quantity =. 0".>3{fields
    price =. 0".>4{fields
    quantities =. quantities,quantity
    amounts =. amounts,quantity*price
  end.
  smoutput 'total: ',":+/amounts
  names =. /:~ ~.regions
  totals =. i.0
  for_name. names do. totals =. totals,+/(regions=name)#amounts end.
  for_i. \:totals do. smoutput (>i{names),': ',":i{totals end.
  for_name. /:~ ~.products do.
    smoutput (>name),': ',":+/(products=name)#quantities
  end.
  days =. /:~ ~.dates
  totals =. i.0
  for_day. days do. totals =. totals,+/(dates=day)#amounts end.
  best =. totals i. >./totals
  smoutput 'best day: ',(>best{days),' (',(":best{totals),')'
)
main ''
