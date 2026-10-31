LF=:10{a.
EMPTY=:i.0 0
LOTKINDS=:;:'receive adjust return count'
CARDKINDS=:'receive';'ship';'fill';'transfer-out';'transfer-in';'adjust';'return';'count';'writedown';'expire';'recall'
CATEGORIES=:'received';'returned';'adjusted-in';'adjusted-out';'shipped';'written-down';'expired';'recalled'
split=:4:0
  <;._1 x,y
)
text_equal=:4:0
  (,x)-:,y
)
number=:3:0
  ,'0' 8!:2 y
)
floor_ratio=:4:0
  <.(x:x)%x:y
)
cents=:3:0
  parts=.'.'split y
  (100*0".0{::parts)+0".1{::parts
)
money=:3:0
  magnitude=.|y
  tail=.number 100|magnitude
  prefix=.''
  if. y<0 do. prefix=.'-' end.
  prefix,(number magnitude floor_ratio 100),'.',((2-#tail)#'0'),tail
)
signed_quantity=:3:0
  if. y>0 do. '+',number y else. number y end.
)
signed_money=:3:0
  if. y>0 do. '+',money y else. money y end.
)
margin=:4:0
  profit=.x
  revenue=.y
  if. revenue=0 do. 'n/a' return. end.
  value=.(1000*|profit)floor_ratio revenue
  prefix=.''
  if. (profit<0)*.value>0 do. prefix=.'-' end.
  prefix,(number value floor_ratio 10),'.',(number 10|value),'%'
)
emit=:3:0
  (y,LF)1!:2(4)
  EMPTY
)
fail=:3:0
  emit 'ERROR ',y
)
iget=:4:0
  (<x,y){I
)
lget=:4:0
  (<x,y){L
)
oget=:4:0
  (<x,y){O
)
iset=:4:0
  I=:y(<x)}I
  EMPTY
)
lset=:4:0
  L=:y(<x)}L
  EMPTY
)
oset=:4:0
  O=:y(<x)}O
  EMPTY
)
warehouse_id=:3:0
  index=.(NW{.WAREHOUSES)i.<,y
  if. index=NW do. _1 else. index end.
)
item_id=:3:0
  index=.(NI{.ITEMCODES)i.<,y
  if. index=NI do. _1 else. index end.
)
warehouse_order=:3:0
  /:NW{.WAREHOUSES
)
item_order=:3:0
  /:NI{.ITEMCODES
)
lot_ids=:3:0
  if. y<0 do. i.NL else. (y iget 4){.y{ITEMLOTS end.
)
holding=:3:0
  'warehouse item'=.y
  ids=.lot_ids item
  rows=.ids{STOCK
  if. warehouse>:0 do. amounts=.warehouse{"1 rows
  else. amounts=.+/"1 NW{."1 rows end.
  costs=.6{"1 ids{L
  (+/amounts),+/amounts*costs
)
backordered=:3:0
  'warehouse item'=.y
  data=.NO{.O
  mask=.((warehouse<0)+.warehouse=0{"1 data)*.((item<0)+.item=1{"1 data)
  +/mask#6{"1 data
)
sales=:3:0
  data=.NO{.O
  if. y>:0 do. data=.data#~y=1{"1 data end.
  (#data),(+/(5{"1 data)-8{"1 data),(+/9{"1 data),+/10{"1 data
)
accumulate=:4:0
  TOTALS=:((x{TOTALS)+y)x}TOTALS
  EMPTY
)
card_entry=:3:0
  'item kind warehouse quantity value'=.y
  if. NB=#B do. B=:((2*#B),6){.B end.
  index=.NB
  NB=:NB+1
  row=.DAY,kind,warehouse,quantity,value,_1
  B=:row index}B
  tail=.item iget 3
  if. tail<0 do. (item,2)iset index
  else. B=:index(<tail,5)}B end.
  (item,3)iset index
)
create_lot=:3:0
  'warehouse item quantity cost day kind'=.y
  index=.NL
  NL=:NL+1
  row=.item,day,quantity,cost,warehouse,kind,cost,0
  L=:row index}L
  STOCK=:quantity(<index,warehouse)}STOCK
  cursor=.item iget 4
  ITEMLOTS=:index(<item,cursor)}ITEMLOTS
  (item,4)iset cursor+1
  position=.index
  while. position>0 do.
    previous=.(position-1){FIFO
    if. (previous lget 1)<:day do. break. end.
    FIFO=:previous position}FIFO
    position=.position-1
  end.
  FIFO=:index position}FIFO
  index
)
issue_stock=:3:0
  'warehouse item quantity'=.y
  parts=.0 3$0
  for_k. i.NL do.
    if. quantity=0 do. break. end.
    lot=.k{FIFO
    held=.(<lot,warehouse){STOCK
    if. (item~:lot lget 0)+.held=0 do. continue. end.
    taken=.quantity<.held
    STOCK=:(held-taken)(<lot,warehouse)}STOCK
    quantity=.quantity-taken
    parts=.parts,lot,taken,lot lget 6
  end.
  parts
)
parts_cost=:3:0
  +/(1{"1 y)*2{"1 y
)
remember_issues=:4:0
  order=.x
  for_part. y do.
    'lot quantity cost'=.part
    if. NU=#U do. U=:((2*#U),5){.U end.
    index=.NU
    NU=:NU+1
    row=.order,lot,quantity,cost,_1
    U=:row index}U
    tail=.order oget 12
    if. tail<0 do. (order,11)oset index
    else. U=:index(<tail,4)}U end.
    (order,12)oset index
  end.
  EMPTY
)
remove_parts=:3:0
  for_part. y do.
    'lot quantity cost'=.part
    (lot,7)lset quantity+lot lget 7
  end.
  EMPTY
)
allocate=:3:0
  'warehouse item'=.y
  for_k. i.NO do.
    if. (warehouse~:k oget 0)+.(item~:k oget 1)+.0=k oget 6 do. continue. end.
    available=.{.holding warehouse,item
    if. available=0 do. return. end.
    quantity=.available<.k oget 6
    parts=.issue_stock warehouse,item,quantity
    cost=.parts_cost parts
    revenue=.quantity*k oget 3
    (k,5)oset quantity+k oget 5
    (k,6)oset (k oget 6)-quantity
    (k,9)oset revenue+k oget 9
    (k,10)oset cost+k oget 10
    k remember_issues parts
    4 accumulate quantity,cost
    card_entry item,2,warehouse,(-quantity),-cost
    emit '  FILL order ',(number k+1),' qty ',(number quantity),' revenue ',(money revenue),' cogs ',(money cost),' profit ',(money revenue-cost),' backorder ',number k oget 6
  end.
  EMPTY
)
sales_fields=:3:0
  profit=.(2{y)-3{y
  ' sold ',(number 1{y),' revenue ',(money 2{y),' cogs ',(money 3{y),' profit ',(money profit),' margin ',profit margin 2{y
)
aging_fields=:4:0
  names=.'0-30';'31-60';'61-90';'91+'
  parts=.0$a:
  for_k. i.4 do.
    if. x do. value=.money k{y else. value=.number k{y end.
    parts=.parts,<(k{::names),' ',value
  end.
  text=.>0{parts
  for_k. 1+i.3 do. text=.text,' ',k{::parts end.
  text
)
age_bucket=:3:0
  if. y<:30 do. 0 elseif. y<:60 do. 1 elseif. y<:90 do. 2 else. 3 end.
)
command=:3:0
  words=.' 'split y
  action=.0{::words
  if. 'DAY'text_equal action do.
    day=.0".1{::words
    if. day<:DAY do. fail 'invalid day ',1{::words else. DAY=:day
      emit 'DAY ',number day end.
    return.
  end.
  if. 'WAREHOUSE'text_equal action do.
    if. 0<:warehouse_id 1{::words do. fail 'duplicate warehouse ',1{::words return. end.
    WAREHOUSES=:(<1{::words)NW}WAREHOUSES
    NW=:NW+1
    emit 'WAREHOUSE ',1{::words
    return.
  end.
  if. 'ITEM'text_equal action do.
    item=.item_id 1{::words
    added=.item<0
    if. added do.
      item=.NI
      NI=:NI+1
      ITEMCODES=:(<1{::words)item}ITEMCODES
      row=.0,_1,_1,_1,0
      I=:row item}I
    end.
    ITEMNAMES=:(<3{::words)item}ITEMNAMES
    (item,0)iset 0".2{::words
    if. added do. label=.' added ' else. label=.' updated ' end.
    emit 'ITEM ',(1{::words),label,(3{::words),' level ',2{::words
    return.
  end.
  if. (<action)e.;:'CANCEL RETURN ORDER' do.
    order=.<:0".1{::words
    if. (order<0)+.order>:NO do. fail 'unknown order ',1{::words return. end.
    entry=.order{O
    warehouse=.0{entry
    item=.1{entry
    pair=.(warehouse{::WAREHOUSES),' ',item{::ITEMCODES
    if. 'CANCEL'text_equal action do.
      quantity=.6{entry
      if. quantity=0 do. fail 'no backorder ',1{::words return. end.
      (order,7)oset quantity+7{entry
      (order,6)oset 0
      emit 'CANCEL order ',(1{::words),' qty ',number quantity
    elseif. 'RETURN'text_equal action do.
      quantity=.0".2{::words
      cost=.cents 3{::words
      if. quantity=0 do. fail 'invalid quantity' return. end.
      returnable=.(5{entry)-8{entry
      if. quantity>returnable do. fail 'return exceeds shipped ',(1{::words),' ',number returnable return. end.
      lot=.create_lot warehouse,item,quantity,cost,DAY,2
      (order,8)oset quantity+8{entry
      (order,9)oset (9{entry)-quantity*3{entry
      (order,10)oset (10{entry)-quantity*cost
      1 accumulate quantity,quantity*cost
      card_entry item,6,warehouse,quantity,quantity*cost
      emit 'RETURN order ',(1{::words),' ',pair,' qty ',(number quantity),' lot ',(number lot+1),' refund ',(money quantity*3{entry),' value ',money quantity*cost
      allocate warehouse,item
    else.
      emit 'ORDER ',(1{::words),' ',pair,' day ',(number 2{entry),' price ',money 3{entry
      emit '  ordered ',(number 4{entry),' shipped ',(number 5{entry),' backorder ',(number 6{entry),' cancelled ',(number 7{entry),' returned ',number 8{entry
      cursor=.11{entry
      while. cursor>:0 do.
        'recordorder lot quantity cost next'=.cursor{U
        emit '  lot ',(number lot+1),' qty ',(number quantity),' cost ',money cost
        cursor=.next
      end.
      emit '  revenue ',(money 9{entry),' cogs ',(money 10{entry),' profit ',money (9{entry)-10{entry
    end.
    return.
  end.
  if. (<action)e.;:'RECEIVE SHIP TRANSFER ADJUST COUNT LOTS' do.
    warehouse=.warehouse_id 1{::words
    if. warehouse<0 do. fail 'unknown warehouse ',1{::words return. end.
    destination=._1
    itemposition=.2
    if. 'TRANSFER'text_equal action do.
      destination=.warehouse_id 2{::words
      if. destination<0 do. fail 'unknown warehouse ',2{::words return. end.
      if. destination=warehouse do. fail 'same warehouse ',1{::words return. end.
      itemposition=.3
    end.
    item=.item_id itemposition{::words
    if. item<0 do. fail 'unknown item ',itemposition{::words return. end.
    pair=.(warehouse{::WAREHOUSES),' ',item{::ITEMCODES
    available=.{.holding warehouse,item
    if. 'LOTS'text_equal action do.
      emit 'LOTS ',pair
      shown=.0
      for_k. i.NL do.
        lot=.k{FIFO
        quantity=.(<lot,warehouse){STOCK
        if. (item=lot lget 0)*.quantity>0 do.
          emit '  lot ',(number lot+1),' day ',(number lot lget 1),' qty ',(number quantity),' cost ',(money lot lget 6),' value ',(money quantity*lot lget 6),' age ',number DAY-lot lget 1
          shown=.shown+1
        end.
      end.
      for_k. i.NO do.
        if. (warehouse=k oget 0)*.(item=k oget 1)*.0<k oget 6 do.
          emit '  backorder order ',(number k+1),' qty ',number k oget 6
          shown=.shown+1
        end.
      end.
      if. shown=0 do. emit '  (none)' end.
      return.
    end.
    positive=.0
    if. 'ADJUST'text_equal action do.
      text=.3{::words
      positive=.'+'={.text
      quantity=.0".}.text
    else. quantity=.0".(itemposition+1){::words end.
    if. (quantity=0)*.-.'COUNT'text_equal action do. fail 'invalid quantity' return. end.
    requiresstock=.('TRANSFER'text_equal action)+.(('ADJUST'text_equal action)*.-.positive)
    if. requiresstock*.available<quantity do. fail 'insufficient stock ',pair,' ',number available return. end.
    if. 'RECEIVE'text_equal action do.
      cost=.cents 4{::words
      day=.0".5{::words
      if. day>DAY do. fail 'future day ',5{::words return. end.
      lot=.create_lot warehouse,item,quantity,cost,day,0
      (item,1)iset cost
      0 accumulate quantity,quantity*cost
      card_entry item,0,warehouse,quantity,quantity*cost
      emit 'RECEIVE ',pair,' lot ',(number lot+1),' qty ',(number quantity),' cost ',(money cost),' day ',(number day),' value ',money quantity*cost
      allocate warehouse,item
    elseif. 'SHIP'text_equal action do.
      price=.cents 4{::words
      filled=.quantity<.available
      parts=.issue_stock warehouse,item,filled
      cost=.parts_cost parts
      order=.NO
      NO=:NO+1
      row=.warehouse,item,DAY,price,quantity,filled,(quantity-filled),0,0,(filled*price),cost,_1,_1
      O=:row order}O
      order remember_issues parts
      if. filled>0 do.
        4 accumulate filled,cost
        card_entry item,1,warehouse,(-filled),-cost
      end.
      emit 'SHIP order ',(number order+1),' ',pair,' shipped ',(number filled),' revenue ',(money filled*price),' cogs ',(money cost),' profit ',(money (filled*price)-cost),' backorder ',number quantity-filled
    elseif. 'TRANSFER'text_equal action do.
      parts=.issue_stock warehouse,item,quantity
      cost=.parts_cost parts
      for_part. parts do.
        'lot taken unitcost'=.part
        STOCK=:(taken+(<lot,destination){STOCK)(<lot,destination)}STOCK
      end.
      card_entry item,3,warehouse,(-quantity),-cost
      card_entry item,4,destination,quantity,cost
      emit 'TRANSFER ',(warehouse{::WAREHOUSES),' -> ',(destination{::WAREHOUSES),' ',(item{::ITEMCODES),' qty ',(number quantity),' value ',(money cost),' lots ',number #parts
      allocate destination,item
    elseif. ('ADJUST'text_equal action)*.positive do.
      cost=.cents 4{::words
      lot=.create_lot warehouse,item,quantity,cost,DAY,1
      2 accumulate quantity,quantity*cost
      card_entry item,5,warehouse,quantity,quantity*cost
      emit 'ADJUST ',pair,' +',(number quantity),' lot ',(number lot+1),' value ',money quantity*cost
      allocate warehouse,item
    elseif. ('ADJUST'text_equal action)+.quantity<available do.
      if. 'ADJUST'text_equal action do.
        removed=.quantity
        kind=.5
      else.
        removed=.available-quantity
        kind=.7
      end.
      parts=.issue_stock warehouse,item,removed
      cost=.parts_cost parts
      remove_parts parts
      3 accumulate removed,cost
      card_entry item,kind,warehouse,(-removed),-cost
      if. 'ADJUST'text_equal action do. text=.'ADJUST ',pair,' -',number removed
      else. text=.'COUNT ',pair,' qty ',(number available),' -> ',(number quantity),' shortage ',number removed end.
      emit text,' value ',money cost
    elseif. quantity=available do.
      emit 'COUNT ',pair,' qty ',(number quantity),' ok'
    else.
      cost=.0>.item iget 1
      added=.quantity-available
      lot=.create_lot warehouse,item,added,cost,DAY,3
      2 accumulate added,added*cost
      card_entry item,7,warehouse,added,added*cost
      emit 'COUNT ',pair,' qty ',(number available),' -> ',(number quantity),' surplus ',(number added),' lot ',(number lot+1),' value ',money added*cost
      allocate warehouse,item
    end.
    return.
  end.
  if. (<action)e.;:'MARKET CARD' do.
    item=.item_id 1{::words
    if. item<0 do. fail 'unknown item ',1{::words return. end.
    if. 'CARD'text_equal action do.
      emit 'CARD ',(1{::words),' ',item{::ITEMNAMES
      cursor=.item iget 2
      quantity=.0
      value=.0
      if. cursor<0 do. emit '  (none)' end.
      while. cursor>:0 do.
        'day kind warehouse dq dv next'=.cursor{B
        quantity=.quantity+dq
        value=.value+dv
        emit '  day ',(number day),' ',(kind{::CARDKINDS),' ',(warehouse{::WAREHOUSES),' ',(signed_quantity dq),' ',(signed_money dv),' balance ',(number quantity),' ',money value
        cursor=.next
      end.
    else.
      price=.cents 2{::words
      count=.0
      quantity=.0
      loss=.0
      lots=.lot_ids item
      for_warehouse. warehouse_order'' do.
        localloss=.0
        for_lot. lots do.
          held=.(<lot,warehouse){STOCK
          oldcost=.lot lget 6
          if. (oldcost>price)*.held>0 do.
            count=.count+1
            quantity=.quantity+held
            difference=.held*oldcost-price
            loss=.loss+difference
            localloss=.localloss+difference
          end.
        end.
        if. localloss>0 do. card_entry item,8,warehouse,0,-localloss end.
      end.
      for_lot. lots do. if. (lot lget 6)>price do. (lot,6)lset price end. end.
      5 accumulate quantity,loss
      emit 'MARKET ',(1{::words),' price ',(money price),' lots ',(number count),' qty ',(number quantity),' loss ',money loss
    end.
    return.
  end.
  if. (<action)e.;:'RECALL TRACE' do.
    lot=.<:0".1{::words
    if. (lot<0)+.lot>:NL do. fail 'unknown lot ',1{::words return. end.
    'item day initialquantity initialcost creator kind cost removed'=.lot{L
    total=.+/NW{.lot{STOCK
    if. ('RECALL'text_equal action)*.total=0 do. fail 'nothing to recall ',1{::words return. end.
    if. 'TRACE'text_equal action do.
      emit 'TRACE lot ',(1{::words),' ',(item{::ITEMCODES),' ',(kind{::LOTKINDS),' ',(creator{::WAREHOUSES),' day ',(number day),' qty ',(number initialquantity),' cost ',money initialcost
    else. emit 'RECALL lot ',(1{::words),' ',(item{::ITEMCODES),' qty ',(number total),' value ',money total*cost end.
    for_warehouse. warehouse_order'' do.
      held=.(<lot,warehouse){STOCK
      if. held>0 do.
        if. 'TRACE'text_equal action do.
          emit '  held ',(warehouse{::WAREHOUSES),' qty ',(number held),' cost ',money cost
        else.
          emit '  ',(warehouse{::WAREHOUSES),' qty ',(number held),' value ',money held*cost
          STOCK=:0(<lot,warehouse)}STOCK
          card_entry item,10,warehouse,(-held),-held*cost
        end.
      end.
    end.
    if. 'RECALL'text_equal action do.
      (lot,7)lset removed+total
      7 accumulate total,total*cost
    else.
      issued=.NO#0
      for_k. i.NU do.
        if. lot=(<k,1){U do.
          order=.(<k,0){U
          issued=.((order{issued)+(<k,2){U)order}issued
        end.
      end.
      for_k. i.NO do. if. 0<k{issued do. emit '  order ',(number k+1),' qty ',number k{issued end. end.
      if. removed>0 do. emit '  removed qty ',number removed end.
    end.
    return.
  end.
  if. 'EXPIRE'text_equal action do.
    days=.0".1{::words
    emit 'EXPIRE ',number days
    allquantity=.0
    allvalue=.0
    for_item. item_order'' do.
      lots=.lot_ids item
      for_warehouse. warehouse_order'' do.
        count=.0
        quantity=.0
        value=.0
        for_lot. lots do.
          held=.(<lot,warehouse){STOCK
          if. (held>0)*.(DAY-lot lget 1)>days do.
            count=.count+1
            quantity=.quantity+held
            value=.value+held*lot lget 6
            STOCK=:0(<lot,warehouse)}STOCK
            (lot,7)lset held+lot lget 7
          end.
        end.
        if. count>0 do.
          card_entry item,9,warehouse,(-quantity),-value
          6 accumulate quantity,value
          allquantity=.allquantity+quantity
          allvalue=.allvalue+value
          emit '  ',(item{::ITEMCODES),' ',(warehouse{::WAREHOUSES),' lots ',(number count),' qty ',(number quantity),' value ',money value
        end.
      end.
    end.
    emit '  total qty ',(number allquantity),' value ',money allvalue
    return.
  end.
  if. (<action)e.;:'VALUE AGING' do.
    warehouse=._1
    if. 2=#words do.
      warehouse=.warehouse_id 1{::words
      if. warehouse<0 do. fail 'unknown warehouse ',1{::words return. end.
    end.
    suffix=.''
    if. warehouse>:0 do. suffix=.' ',1{::words end.
    if. 'VALUE'text_equal action do.
      emit 'VALUE',suffix
      for_item. item_order'' do.
        'quantity value'=.holding warehouse,item
        if. quantity>0 do.
          emit '  ',(item{::ITEMCODES),' qty ',(number quantity),' value ',(money value),' avg ',money value floor_ratio quantity
          if. warehouse<0 do.
            for_location. warehouse_order'' do.
              'localquantity localvalue'=.holding location,item
              if. localquantity>0 do. emit '    ',(location{::WAREHOUSES),' qty ',(number localquantity),' value ',money localvalue end.
            end.
          end.
        end.
      end.
      'quantity value'=.holding warehouse,_1
      emit '  total qty ',(number quantity),' value ',money value
    else.
      emit 'AGING',suffix,' day ',number DAY
      totalquantity=.4#0
      totalvalue=.4#0
      for_item. item_order'' do.
        quantities=.4#0
        count=.0
        for_lot. lot_ids item do.
          if. warehouse>:0 do. held=.(<lot,warehouse){STOCK else. held=.+/NW{.lot{STOCK end.
          bucket=.age_bucket DAY-lot lget 1
          quantities=.(held+bucket{quantities)bucket}quantities
          totalquantity=.(held+bucket{totalquantity)bucket}totalquantity
          totalvalue=.((held*lot lget 6)+bucket{totalvalue)bucket}totalvalue
          count=.count+held
        end.
        if. count>0 do. emit '  ',(item{::ITEMCODES),' ',0 aging_fields quantities end.
      end.
      emit '  total ',0 aging_fields totalquantity
      emit '  value ',1 aging_fields totalvalue
    end.
    return.
  end.
  if. (<action)e.;:'ITEMS REORDER MARGIN TOP' do.
    if. 'TOP'text_equal action do. emit 'TOP ',1{::words else. emit action end.
    shown=.0
    order=.item_order''
    summaries=.(NI,4)$0
    if. (<action)e.;:'MARGIN TOP' do.
      for_item. i.NI do. summaries=.(sales item)item}summaries end.
    end.
    if. 'TOP'text_equal action do.
      ranking=.i.0
      keys=.0 2$0
      for_item. order do.
        values=.item{summaries
        if. 0<0{values do.
          ranking=.ranking,item
          profit=.(2{values)-3{values
          keys=.keys,(-profit),-2{values
        end.
      end.
      ranking=.( /:keys){ranking
      limit=.(0".1{::words)<.#ranking
      for_k. i.limit do.
        item=.k{ranking
        values=.item{summaries
        profit=.(2{values)-3{values
        emit '  ',(number k+1),' ',(item{::ITEMCODES),' profit ',(money profit),' revenue ',(money 2{values),' margin ',profit margin 2{values
        shown=.shown+1
      end.
    else.
      for_item. order do.
        held=.{.holding _1,item
        backorder=.backordered _1,item
        if. 'ITEMS'text_equal action do.
          cost=.'none'
          if. 0<:item iget 1 do. cost=.money item iget 1 end.
          emit '  ',(item{::ITEMCODES),' ',(item{::ITEMNAMES),' level ',(number item iget 0),' onhand ',(number held),' backorder ',(number backorder),' cost ',cost
          shown=.shown+1
        elseif. 'REORDER'text_equal action do.
          if. (held-backorder)<:item iget 0 do.
            emit '  ',(item{::ITEMCODES),' ',(item{::ITEMNAMES),' onhand ',(number held),' backorder ',(number backorder),' level ',number item iget 0
            shown=.shown+1
          end.
        elseif. 0<(<item,0){summaries do.
          emit '  ',(item{::ITEMCODES),sales_fields item{summaries
        end.
      end.
      if. 'MARGIN'text_equal action do. emit '  total',sales_fields sales _1 end.
    end.
    if. (shown=0)*.-.'MARGIN'text_equal action do. emit '  (none)' end.
    return.
  end.
  if. 'BACKORDERS'text_equal action do.
    emit 'BACKORDERS'
    shown=.0
    for_k. i.NO do.
      if. 0<k oget 6 do.
        emit '  order ',(number k+1),' ',((k oget 0){::WAREHOUSES),' ',((k oget 1){::ITEMCODES),' qty ',(number k oget 6),' day ',(number k oget 2),' price ',money k oget 3
        shown=.shown+1
      end.
    end.
    if. shown=0 do. emit '  (none)' end.
  elseif. 'STATUS'text_equal action do.
    emit 'STATUS'
    if. NW=0 do. emit '  (none)' end.
    for_warehouse. warehouse_order'' do.
      skus=.0
      for_item. i.NI do. if. 0<{.holding warehouse,item do. skus=.skus+1 end. end.
      'quantity value'=.holding warehouse,_1
      emit '  ',(warehouse{::WAREHOUSES),' skus ',(number skus),' qty ',(number quantity),' value ',(money value),' backorder ',number backordered warehouse,_1
    end.
  else.
    emit 'SUMMARY'
    for_k. i.8 do. emit '  ',(k{::CATEGORIES),' qty ',(number (<k,0){TOTALS),' value ',money (<k,1){TOTALS end.
    'quantity value'=.holding _1 _1
    emit '  on-hand qty ',(number quantity),' value ',money value
    openorders=.+/0<6{"1 NO{.O
    emit '  orders ',(number NO),' open ',(number openorders),' backorder ',number backordered _1 _1
  end.
  EMPTY
)
main=:3:0
  DAY=:1
  WAREHOUSES=:20$<''
  NW=:0
  ITEMCODES=:100$<''
  ITEMNAMES=:100$<''
  I=:100 5$0
  NI=:0
  L=:2000 8$0
  STOCK=:2000 20$0
  ITEMLOTS=:100 2000$0
  FIFO=:2000#0
  NL=:0
  O=:2000 13$0
  NO=:0
  U=:16 5$0
  NU=:0
  B=:16 6$0
  NB=:0
  TOTALS=:8 2$0
  input=.1!:1(3)
  if. LF~:{:input do. input=.input,LF end.
  lines=.<;._2 input
  count=.0".0{::lines
  for_k. 1+i.count do. command k{::lines end.
  EMPTY
)
main''
