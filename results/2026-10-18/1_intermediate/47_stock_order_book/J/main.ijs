LF =: 10{a.
number =: 3 : ',''0'' 8!:2 y'
eq =: 4 : '(,x)-:,y'
split =: 4 : '<;._1 x,y'
join =: 4 : 0
 r =. ''
 for_i. i.#y do.
  if. i do. r =. r,x end.
  r =. r,i{::y
 end.
 r
)
words =: 3 : 0
 r =. 0$a:
 for_v. y do.
  v =. >v
  if. 2~:3!:0 v do. v =. number v end.
  r =. r,<,v
 end.
 ' ' join r
)
emit =: 3 : 'Output =: Output,<y'
say =: 3 : 'emit words y'
fail =: 3 : 0
 Error =: y
 throw.
)
fixed =: 3 : '(number <.y%100),''.'',_2{.''00'',number 100|y'
avg =: 4 : 'fixed <.(100*x)%y'
Ids =: Names =: Hist =: 0$a:
Trader =: Kind =: Side =: Cond =: Price =: Trigger =: Peak =: Qty =: Left =: Visible =: Filled =: Value =: Priority =: State =: i.0
Bought =: Sold =: Cash =: Fees =: Risk =: i.0
Trades =: 0 7$0
Next =: 1
Halted =: Band =: MakerFee =: TakerFee =: 0
Tick =: Lot =: 1
Types =: ;:'LIMIT MARKET STOP STOPLIMIT ICEBERG'
States =: ;:'PENDING OPEN PARTIAL FILLED CANCELLED EXECUTING'
Sides =: ;:'BUY SELL'
resting =: 3 : '(y{State)e.1 2'
active =: 3 : '(y{State)e.0 1 2'
register =: 3 : 0
 n =. Names i.<,y
 if. n=#Names do.
  Names =: Names,<,y
  Bought =: Bought,0
  Sold =: Sold,0
  Cash =: Cash,0
  Fees =: Fees,0
  Risk =: Risk,_1
 end.
 n
)
trader =: 3 : 0
 n =. Names i.<,y
 if. n=#Names do. fail 'unknown trader' end.
 n
)
order =: 3 : 0
 n =. Ids i.<,y
 if. n=#Ids do. fail 'unknown order' end.
 n
)
last =: 3 : 0
 if. #Trades do. 0{_1{Trades else. _1 end.
)
net =: 3 : '(y{Bought)-y{Sold'
pnl =: 3 : '(y{Cash)+(net y)*0>.last '''''
volume =: 3 : '(y{Bought)+y{Sold'
book =: 3 : 0
 sel =. I.(Side=y)*.State e.1 2
 if. y=0 do. key =. -sel{Price else. key =. sel{Price end.
 (/:key,.sel{Priority){sel
)
levels =: 3 : 0
 result =. 0 3$0
 for_i. book y do.
  p =. i{Price
  if. #result do.
   if. p=0{_1{result do.
    row =. _1{result
    result =. (row+0,(i{Visible),1) ((#result)-1)}result
    continue.
   end.
  end.
  result =. result,p,(i{Visible),1
 end.
 result
)
exposure =: 3 : 0
 't s excluded' =. y
 total =. (net t)*1-2*s
 for_i. I.(Trader=t)*.(Side=s)*.State e.0 1 2 do.
  if. i~:excluded do. total =. total+i{Left end.
 end.
 total
)
checkrisk =: 3 : 0
 't s q excluded' =. y
 if. t=#Names do. return. end.
 if. (t{Risk)<0 do. return. end.
 if. (q+exposure t,s,excluded)>t{Risk do. fail 'risk limit' end.
)
checkband =: 3 : 0
 l =. last ''
 if. (Band>0)*.(l>:0)*.(|y-l)>Band do. fail 'outside band' end.
)
record =: 4 : 'Hist =: (<(x{::Hist),<y) x}Hist'
orderline =: 3 : 'words ''ORDER'';(y{::Ids);((y{State){::States);(number y{Filled),''/'',number y{Qty'
details =: 3 : 0
 if. (y{Price)<0 do. p =. '-' else. p =. number y{Price end.
 if. y{Filled do. av =. (y{Value)avg y{Filled else. av =. '-' end.
 r =. words (y{::Ids);((y{Trader){::Names);((y{Kind){::Types);((y{Side){::Sides);p;((y{State){::States);((number y{Filled),'/',number y{Qty);'avg';av
 if. (y{Trigger)>:0 do. r =. r,' trigger ',number y{Trigger end.
 r
)
position =: 3 : 'words ''POSITION'';(y{::Names);''bought'';(y{Bought);''sold'';(y{Sold);''net'';(net y);''cash'';(y{Cash);''fees'';(y{Fees);''pnl'';pnl y'
tradeline =: 3 : 0
 'p q b s tk bf sf' =. y{Trades
 words 'TRADE';(y+1);p;q;(b{::Ids);((b{Trader){::Names);(s{::Ids);(s{Trader){::Names
)
matches =: 4 : 0
 if. (x{Price)<0 do. 1 return. end.
 if. (x{Side)=0 do. y<:x{Price else. y>:x{Price end.
)
triggered =: 4 : 0
 if. (x{Side)=0 do. y>:x{Trigger else. y<:x{Trigger end.
)
execute_order =: 3 : 0
 while. y{Left do.
  bk =. book 1-y{Side
  if. 0=#bk do. break. end.
  m =. {.bk
  if. -.y matches m{Price do. break. end.
  if. (y{Trader)=m{Trader do.
   say 'STP';(m{::Ids);m{Left
   m record 'STP ',number m{Left
   Left =: 0 m}Left
   State =: 4 m}State
   continue.
  end.
  q =. (y{Left)<.m{Visible
  p =. m{Price
  if. (y{Side)=0 do. b =. y [ s =. m [ bf =. q*TakerFee [ sf =. q*MakerFee
  else. b =. m [ s =. y [ bf =. q*MakerFee [ sf =. q*TakerFee end.
  Trades =: Trades,p,q,b,s,y,bf,sf
  for_i. y,m do.
   Left =: ((i{Left)-q) i}Left
   Filled =: ((i{Filled)+q) i}Filled
   Value =: ((i{Value)+p*q) i}Value
   i record words 'FILL';(#Trades);p;q
  end.
  Visible =: ((m{Visible)-q) m}Visible
  bt =. b{Trader
  st =. s{Trader
  Bought =: ((bt{Bought)+q) bt}Bought
  Sold =: ((st{Sold)+q) st}Sold
  Cash =: ((bt{Cash)-bf+p*q) bt}Cash
  Cash =: ((st{Cash)+(p*q)-sf) st}Cash
  Fees =: ((bt{Fees)+bf) bt}Fees
  Fees =: ((st{Fees)+sf) st}Fees
  emit tradeline (#Trades)-1
  if. 0=m{Left do. State =: 3 m}State
  else.
   State =: 2 m}State
   if. 0=m{Visible do.
    Priority =: Next m}Priority
    Next =: Next+1
    v =. (m{Peak)<.m{Left
    Visible =: v m}Visible
    h =. (m{Left)-v
    m record words 'REFRESH';v;h
    say 'REFRESH';(m{::Ids);v;h
   end.
  end.
 end.
)
post =: 4 : 0
 if. 0=y{Left do. State =: 3 y}State
 elseif. x+.((y{Kind)e.3 4)+.((y{Kind)=0)*.(y{Cond)~:1 do.
  Priority =: Next y}Priority
  Next =: Next+1
  v =. y{Left
  if. (y{Peak)>:0 do. v =. v<.y{Peak end.
  Visible =: v y}Visible
  State =: (1+0<y{Filled) y}State
  y record words 'REST';(y{Price);v
 else.
  y record 'EXPIRE ',number y{Left
  Left =: 0 y}Left
  State =: 4 y}State
 end.
 emit orderline y
)
trigger_stops =: 3 : 0
 while. #Trades do.
  selected =. i.0
  for_i. I.State=0 do. if. i triggered last '' do. selected =. selected,i end. end.
  if. 0=#selected do. break. end.
  State =: 5 selected}State
  for_i. selected do.
   say 'TRIGGER';i{::Ids
   i record 'TRIGGER'
   execute_order i
   0 post i
  end.
 end.
)
cancel =: 3 : 0
 y record 'CANCEL ',number y{Left
 Left =: 0 y}Left
 State =: 4 y}State
 emit orderline y
)
bar =: 3 : 0
 p =. 0{"1 y
 words 'open';({.p);'high';(>./p);'low';(<./p);'close';({:p);'volume';+/1{"1 y
)
new_order =: 4 : 0
 kind =. Types i.<x
 id =. 0{::y
 name =. 1{::y
 s =. Sides i.2{y
 p =. r =. peak =. _1
 cond =. 0
 select. kind
 case. 0 do. p =. 0".3{::y [ q =. 0".4{::y
  if. 6=#y do. cond =. 1+('IOC';'FOK';'POSTONLY')i.5{y end.
 case. 1 do. q =. 0".3{::y
 case. 2 do. r =. 0".3{::y [ q =. 0".4{::y
 case. 3 do. r =. 0".3{::y [ p =. 0".4{::y [ q =. 0".5{::y
 case. 4 do. p =. 0".3{::y [ q =. 0".4{::y [ peak =. 0".5{::y
 end.
 if. Halted do. fail 'halted' end.
 if. (<id)e.Ids do. fail 'duplicate id' end.
 if. 0 e.p,r do. fail 'invalid price' end.
 if. q=0 do. fail 'invalid quantity' end.
 prices =. (p,r)#~(p,r)>:0
 if. +./0~:Tick|prices do. fail 'invalid tick' end.
 if. 0~:Lot|q do. fail 'invalid lot' end.
 if. kind=4 do.
  if. (peak=0)+.(peak>q)+.0~:Lot|peak do. fail 'invalid peak' end.
 end.
 if. r>:0 do.
  l =. last ''
  if. l>:0 do.
   if. ((s=0)*.r<:l)+.((s=1)*.r>:l) do. fail 'invalid trigger' end.
  end.
 end.
 if. p>:0 do. checkband p end.
 t =. Names i.<name
 checkrisk t,s,q,_1
 bk =. book 1-s
 if. cond e.2 3 do.
  available =. 0
  for_i. bk do.
   matchable =. ((s=0)*.(i{Price)<:p)+.((s=1)*.(i{Price)>:p)
   if. (cond=3)*.matchable do. fail 'would cross' end.
   if. matchable*.t~:i{Trader do. available =. available+i{Left end.
  end.
  if. (cond=2)*.available<q do. fail 'unfillable' end.
 end.
 t =. register name
 i =. #Ids
 Ids =: Ids,<id
 Trader =: Trader,t
 Kind =: Kind,kind
 Side =: Side,s
 Cond =: Cond,cond
 Price =: Price,p
 Trigger =: Trigger,r
 Peak =: Peak,peak
 Qty =: Qty,q
 Left =: Left,q
 Filled =: Filled,0
 Value =: Value,0
 Visible =: Visible,0
 Priority =: Priority,0
 State =: State,0
 Hist =: Hist,<,<'ACCEPT'
 if. r>:0 do. emit orderline i
 else.
  if. cond~:3 do. execute_order i end.
  0 post i
  trigger_stops ''
 end.
)
handle =: 4 : 0
 if. (<x)e.Types do. x new_order y return. end.
 select. x
 case. 'CANCEL' do.
  i =. order 0{::y
  if. -.active i do. fail 'not open' end.
  cancel i
 case. 'REPLACE' do.
  if. Halted do. fail 'halted' end.
  i =. order 0{::y
  if. -.resting i do. fail 'not open' end.
  p =. 0".1{::y
  q =. 0".2{::y
  moved =. p~:i{Price
  if. p=0 do. fail 'invalid price' end.
  if. q=0 do. fail 'invalid quantity' end.
  if. moved*.0~:Tick|p do. fail 'invalid tick' end.
  if. 0~:Lot|q do. fail 'invalid lot' end.
  if. (-.moved)*.q=i{Left do. fail 'no change' end.
  if. moved do. checkband p end.
  if. q>i{Left do. checkrisk (i{Trader),(i{Side),q,i end.
  kept =. (-.moved)*.q<i{Left
  Qty =: ((i{Filled)+q) i}Qty
  Left =: q i}Left
  Price =: p i}Price
  label =. kept{::'lost';'kept'
  i record words 'REPLACE';p;q;label
  say 'REPLACE';(i{::Ids);label
  if. kept do.
   Visible =: (q<.i{Visible) i}Visible
   emit orderline i
  else.
   State =: 5 i}State
   execute_order i
   1 post i
   trigger_stops ''
  end.
 case. 'CANCELALL';'ORDERS' do.
  t =. trader 0{::y
  selected =. I.(Trader=t)*.State e.0 1 2
  say x;(t{::Names);#selected
  for_i. selected do.
   if. x eq 'CANCELALL' do. cancel i else. emit details i end.
  end.
 case. 'HALT' do.
  if. Halted do. fail 'already halted' end.
  Halted =: 1
  emit x
 case. 'RESUME' do.
  if. -.Halted do. fail 'not halted' end.
  Halted =: 0
  emit x
 case. 'RISK' do.
  t =. register 0{::y
  m =. 0".1{::y
  Risk =: m t}Risk
  say x;(t{::Names);m;'exposure buy';(exposure t,0,_1);'sell';exposure t,1,_1
 case. 'FEE' do.
  a =. 0".0{::y
  b =. 0".1{::y
  if. (a+b)<0 do. fail 'invalid fee' end.
  MakerFee =: a
  TakerFee =: b
  say x;'maker';a;'taker';b
 case. 'BAND' do. Band =: 0".0{::y [ say x;0{::y
 case. 'TICK';'LOT' do.
  n =. 0".0{::y
  if. n=0 do. fail 'invalid size' end.
  if. x eq 'TICK' do. Tick =: n else. Lot =: n end.
  say x;n
 case. 'BOOK' do.
  n =. 0".0{::y
  if. n=0 do. fail 'invalid depth' end.
  bids =. levels 0
  asks =. levels 1
  say x;'bids';(#bids);'asks';#asks
  for_row. |.(n<.#asks){.asks do. say 'ASK';(0{row);(1{row);2{row end.
  for_row. (n<.#bids){.bids do. say 'BID';(0{row);(1{row);2{row end.
 case. 'STATUS' do. emit 'STATUS ',details order 0{::y
 case. 'HISTORY' do.
  i =. order 0{::y
  h =. i{::Hist
  say x;(i{::Ids);#h
  for_line. h do. emit >line end.
 case. 'POSITION' do. emit position trader 0{::y
 case. 'FILLS' do.
  t =. trader 0{::y
  selected =. i.0
  for_i. i.#Trades do.
   if. t e.(2 3{i{Trades){Trader do. selected =. selected,i end.
  end.
  say x;(t{::Names);#selected
  n =. 0
  for_i. selected do.
   'p q b s tk bf sf' =. i{Trades
   if. t=b{Trader do. side =. 'BUY' [ oi =. b [ fee =. bf [ n =. n+q
   else. side =. 'SELL' [ oi =. s [ fee =. sf [ n =. n-q end.
   role =. (oi=tk){::'MAKER';'TAKER'
   say (i+1);side;p;q;(oi{::Ids);role;'fee';fee;'net';n
  end.
 case. 'LAST' do.
  if. #Trades do. say x;(0{_1{Trades);1{_1{Trades else. emit 'LAST none' end.
 case. 'VWAP' do.
  if. #Trades do.
   v =. +/1{"1 Trades
   a =. +/(0{"1 Trades)*1{"1 Trades
   say x;(a avg v);'volume';v;'trades';#Trades
  else. emit 'VWAP none' end.
 case. 'SPREAD' do.
  bids =. book 0
  asks =. book 1
  b =. a =. 'none'
  if. #bids do. b =. number ({.bids){Price end.
  if. #asks do. a =. number ({.asks){Price end.
  text =. words x;'bid';b;'ask';a
  if. (0<#bids)*.0<#asks do.
   bp =. ({.bids){Price
   ap =. ({.asks){Price
   mid =. (number <.(bp+ap)%2),'.',((2|bp+ap){'05')
   text =. text,' ',words 'spread';(ap-bp);'mid';mid
  end.
  emit text
 case. 'IMPACT' do.
  s =. Sides i.0{y
  q =. 0".1{::y
  if. q=0 do. fail 'invalid quantity' end.
  ls =. levels 1-s
  r =. q [ cost =. used =. worst =. 0
  for_row. ls do.
   if. r=0 do. break. end.
   'p v count' =. row
   u =. r<.v
   r =. r-u
   cost =. cost+u*p
   worst =. p
   used =. used+1
  end.
  if. r do. say x;(s{::Sides);q;'insufficient';+/1{"1 ls
  else. say x;(s{::Sides);q;'avg';(cost avg q);'worst';worst;'levels';used end.
 case. 'TRADES';'BARS' do.
  k =. 0".0{::y
  if. k=0 do. fail 'invalid count' end.
  if. x eq 'TRADES' do.
   n =. k<.#Trades
   say x;n;'of';#Trades
   for_i. ((#Trades)-n)+i.n do. emit tradeline i end.
  else.
   n =. >.(#Trades)%k
   say x;n
   for_i. i.n do. say (i+1);bar (k<.(#Trades)-i*k){.(i*k)}.Trades end.
  end.
 case. 'RANK' do.
  ns =. /:s:Names
  keys =. 0 2$0
  for_i. ns do. keys =. keys,(-pnl i),-volume i end.
  ns =. (/:keys){ns
  say x;#ns
  for_j. i.#ns do.
   i =. j{ns
   say (j+1);(i{::Names);'pnl';(pnl i);'volume';volume i
  end.
 case. 'FLOW' do.
  b =. s =. 0
  for_row. Trades do.
   if. (4{row){Side do. s =. s+1{row else. b =. b+1{row end.
  end.
  say x;'buy';b;'sell';s;'net';b-s
 case. 'SUMMARY' do.
  if. #Trades do.
   p =. 0{"1 Trades
   say x;'trades';(#Trades);'volume';(+/1{"1 Trades);'open';({.p);'high';(>./p);'low';(<./p);'close';({:p);'fees';+/,5 6{"1 Trades
  else. emit 'SUMMARY trades 0' end.
  for_t. /:s:Names do. emit position t end.
 end.
)
main =: 3 : 0
 n =. 0".1!:1 3
 for_i. i.n do.
  fields =. ' ' split 1!:1 3
  cmd =. 0{::fields
  Output =: 0$a:
  try. cmd handle }.fields
  catcht.
   if. (<cmd)e.;:'LIMIT MARKET STOP STOPLIMIT ICEBERG CANCEL REPLACE' do. say 'REJECT';(1{::fields);Error
   else. say 'ERROR';Error end.
  end.
  for_line. Output do. ((>line),LF)1!:2 4 end.
 end.
 i.0
)
main ''
