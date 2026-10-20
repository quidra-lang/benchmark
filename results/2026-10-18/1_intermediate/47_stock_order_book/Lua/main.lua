local function emit(...)
    local a={...}
    for i,v in ipairs(a) do
        a[i]=tostring(v)
    end
    io.write(table.concat(a,' '),'\n')
end
local function check(bad,reason)
    if bad then
        error(reason,0)
    end
end
local function dec(n)
    return string.format('%d.%02d',n//100,n%100)
end
local function opposite(s)
    return s=='BUY' and 'SELL' or 'BUY'
end
local orders, sequence, traders, trades = {}, {}, {}, {}
local maker,taker,band,priority,tick,lot,halted=0,0,0,0,1,1,false
local function active(o)
    return o.status=='PENDING' or o.status=='OPEN' or o.status=='PARTIAL'
end
local function resting(o)
    return o.status=='OPEN' or o.status=='PARTIAL'
end
local function matches(o,p)
    return o.price==nil or (o.side=='BUY' and p<=o.price) or (o.side=='SELL' and p>=o.price)
end
local function triggered(o,p)
    return (o.side=='BUY' and p>=o.trigger) or (o.side=='SELL' and p<=o.trigger)
end
local function last()
    return #trades>0 and trades[#trades].price or nil
end
local function register(name)
    if not traders[name] then
        traders[name]={name=name,bought=0,sold=0,cash=0,fees=0}
    end
    return traders[name]
end
local function get_order(id)
    check(not orders[id],'unknown order')
    return orders[id]
end
local function get_trader(name)
    check(not traders[name],'unknown trader')
    return traders[name]
end
local function best(side)
    local b=nil
    for _,o in ipairs(sequence) do
        if resting(o) and o.side==side and (not b or (o.price==b.price and o.priority<b.priority) or (side=='BUY' and o.price>b.price) or (side=='SELL' and o.price<b.price)) then
            b=o
        end
    end
    return b
end
local function active_orders(name)
    local a={}
    for _,o in ipairs(sequence) do
        if o.trader==name and active(o) then
            a[#a+1]=o
        end
    end
    return a
end
local function exposure(name,side,excluded)
    local t=traders[name]
    local total=(t.bought-t.sold)*(side=='BUY' and 1 or -1)
    for _,o in ipairs(active_orders(name)) do
        if o.side==side and o~=excluded then
            total=total+o.remaining
        end
    end
    return total
end
local function risk(name,side,q,excluded)
    local t=traders[name]
    if t and t.limit then
        check(exposure(name,side,excluded)+q>t.limit,'risk limit')
    end
end
local function check_band(p)
    local l=last()
    check(band>0 and l and math.abs(p-l)>band,'outside band')
end
local function order_line(o)
    return 'ORDER '..o.id..' '..o.status..' '..o.filled..'/'..o.quantity
end
local function details(o)
    local text=table.concat({o.id,o.trader,o.kind,o.side,o.price or '-',o.status,o.filled..'/'..o.quantity,'avg',o.filled==0 and '-' or dec(o.value*100//o.filled)},' ')
    return text..(o.trigger and ' trigger '..o.trigger or '')
end
local function pnl(t)
    return t.cash+(t.bought-t.sold)*(last() or 0)
end
local function position(t)
    emit('POSITION',t.name,'bought',t.bought,'sold',t.sold,'net',t.bought-t.sold,'cash',t.cash,'fees',t.fees,'pnl',pnl(t))
end
local function trade_line(t)
    return table.concat({'TRADE',t.number,t.price,t.quantity,t.buy.id,t.buy.trader,t.sell.id,t.sell.trader},' ')
end
local function levels(side)
    local map,ls={},{}
    for _,o in ipairs(sequence) do
        if resting(o) and o.side==side then
            if not map[o.price] then
                map[o.price]={o.price,0,0}
                ls[#ls+1]=map[o.price]
            end
            local l=map[o.price]
            l[2]=l[2]+o.visible
            l[3]=l[3]+1
        end
    end
    table.sort(ls,function(a,b)
        if side=='BUY' then
            return a[1]>b[1]
        end
        return a[1]<b[1]
    end)
    return ls
end
local function cancel(o)
    o.history[#o.history+1]='CANCEL '..o.remaining
    o.remaining=0
    o.visible=0
    o.status='CANCELLED'
    emit(order_line(o))
end
local function match(o)
    while o.remaining>0 do
        local y=best(opposite(o.side))
        if not y or not matches(o,y.price) then
            break
        end
        if y.trader==o.trader then
            emit('STP',y.id,y.remaining)
            y.history[#y.history+1]='STP '..y.remaining
            y.remaining=0
            y.visible=0
            y.status='CANCELLED'
        else
            local q,p=math.min(o.remaining,y.visible),y.price
            local buy,sell,bf,sf
            if o.side=='BUY' then
                buy,sell,bf,sf=o,y,q*taker,q*maker
            else
                buy,sell,bf,sf=y,o,q*maker,q*taker
            end
            local tr={number=#trades+1,price=p,quantity=q,buy=buy,sell=sell,taker=o,buy_fee=bf,sell_fee=sf}
            trades[#trades+1]=tr
            for _,x in ipairs({o,y}) do
                x.remaining=x.remaining-q
                x.filled=x.filled+q
                x.value=x.value+q*p
                x.history[#x.history+1]='FILL '..tr.number..' '..p..' '..q
            end
            y.visible=y.visible-q
            local bt,st=traders[buy.trader],traders[sell.trader]
            bt.bought=bt.bought+q
            bt.cash=bt.cash-q*p-bf
            bt.fees=bt.fees+bf
            st.sold=st.sold+q
            st.cash=st.cash+q*p-sf
            st.fees=st.fees+sf
            emit(trade_line(tr))
            y.status=y.remaining==0 and 'FILLED' or 'PARTIAL'
            if y.remaining>0 and y.visible==0 then
                priority=priority+1
                y.priority=priority
                y.visible=math.min(y.peak,y.remaining)
                local h=y.remaining-y.visible
                y.history[#y.history+1]='REFRESH '..y.visible..' '..h
                emit('REFRESH',y.id,y.visible,h)
            end
        end
    end
end
local function finish(o,force)
    if o.remaining==0 then
        o.status='FILLED'
    elseif force or (o.kind=='LIMIT' and o.condition~='IOC') or o.kind=='ICEBERG' or o.kind=='STOPLIMIT' then
        priority=priority+1
        o.priority=priority
        o.visible=math.min(o.peak or o.remaining,o.remaining)
        o.status=o.filled==0 and 'OPEN' or 'PARTIAL'
        o.history[#o.history+1]='REST '..o.price..' '..o.visible
    else
        o.history[#o.history+1]='EXPIRE '..o.remaining
        o.remaining=0
        o.status='CANCELLED'
    end
    emit(order_line(o))
end
local function triggers()
    while last() do
        local selected,l={},last()
        for _,o in ipairs(sequence) do
            if o.status=='PENDING' and triggered(o,l) then
                selected[#selected+1]=o
                o.status='TRIGGERING'
            end
        end
        if #selected==0 then
            break
        end
        for _,o in ipairs(selected) do
            emit('TRIGGER',o.id)
            o.history[#o.history+1]='TRIGGER'
            match(o)
            finish(o)
        end
    end
end
local function submit(c,a)
    local id,name,side=a[1],a[2],a[3]
    local p,r,q,peak,cond
    if c=='MARKET' then
        q=tonumber(a[4])
    elseif c=='STOP' then
        r,q=tonumber(a[4]),tonumber(a[5])
    elseif c=='STOPLIMIT' then
        r,p,q=tonumber(a[4]),tonumber(a[5]),tonumber(a[6])
    else
        p,q=tonumber(a[4]),tonumber(a[5])
        if c=='ICEBERG' then
            peak=tonumber(a[6])
        elseif c=='LIMIT' then
            cond=a[6]
        end
    end
    check(halted,'halted')
    check(orders[id]~=nil,'duplicate id')
    check(p==0 or r==0,'invalid price')
    check(q==0,'invalid quantity')
    check((p and p%tick~=0) or (r and r%tick~=0),'invalid tick')
    check(q%lot~=0,'invalid lot')
    local o={id=id,trader=name,kind=c,side=side,price=p,trigger=r,peak=peak,condition=cond,quantity=q,remaining=q,visible=0,filled=0,value=0,priority=0,status='INCOMING',history={'ACCEPT'}}
    check(peak and (peak==0 or peak>q or peak%lot~=0),'invalid peak')
    check(r and last() and triggered(o,last()),'invalid trigger')
    if p then
        check_band(p)
    end
    risk(name,side,q)
    local y=best(opposite(side))
    check(cond=='POSTONLY' and y and matches(o,y.price),'would cross')
    local available=0
    for _,x in ipairs(sequence) do
        if resting(x) and x.side==opposite(side) and x.trader~=name and matches(o,x.price) then
            available=available+x.remaining
        end
    end
    check(cond=='FOK' and available<q,'unfillable')
    register(name)
    orders[id]=o
    sequence[#sequence+1]=o
    if r then
        o.status='PENDING'
        emit(order_line(o))
    else
        if cond~='POSTONLY' then
            match(o)
        end
        finish(o)
        triggers()
    end
end
local function replace(a)
    local id,p,q=a[1],tonumber(a[2]),tonumber(a[3])
    check(halted,'halted')
    local o=get_order(id)
    check(not resting(o),'not open')
    check(p==0,'invalid price')
    check(q==0,'invalid quantity')
    local moved=p~=o.price
    check(moved and p%tick~=0,'invalid tick')
    check(q%lot~=0,'invalid lot')
    check(not moved and q==o.remaining,'no change')
    if moved then
        check_band(p)
    end
    if q>o.remaining then
        risk(o.trader,o.side,q,o)
    end
    local kept=not moved and q<o.remaining
    local word=kept and 'kept' or 'lost'
    o.quantity=o.filled+q
    o.remaining=q
    o.history[#o.history+1]='REPLACE '..p..' '..q..' '..word
    emit('REPLACE',id,word)
    if kept then
        o.visible=math.min(o.visible,q)
        emit(order_line(o))
    else
        o.price=p
        o.status='INCOMING'
        match(o)
        finish(o,true)
        triggers()
    end
end
local function bar(ts)
    local high,low,vol=ts[1].price,ts[1].price,0
    for _,t in ipairs(ts) do
        high=math.max(high,t.price)
        low=math.min(low,t.price)
        vol=vol+t.quantity
    end
    return 'open '..ts[1].price..' high '..high..' low '..low..' close '..ts[#ts].price..' volume '..vol
end
local function execute(c,a)
    if c=='LIMIT' or c=='MARKET' or c=='STOP' or c=='STOPLIMIT' or c=='ICEBERG' then
        submit(c,a)
    elseif c=='CANCEL' then
        local o=get_order(a[1])
        check(not active(o),'not open')
        cancel(o)
    elseif c=='REPLACE' then
        replace(a)
    elseif c=='CANCELALL' then
        get_trader(a[1])
        local os=active_orders(a[1])
        emit(c,a[1],#os)
        for _,o in ipairs(os) do
            cancel(o)
        end
    elseif c=='HALT' then
        check(halted,'already halted')
        halted=true
        emit(c)
    elseif c=='RESUME' then
        check(not halted,'not halted')
        halted=false
        emit(c)
    elseif c=='RISK' then
        register(a[1]).limit=tonumber(a[2])
        emit(c,a[1],a[2],'exposure buy',exposure(a[1],'BUY'),'sell',exposure(a[1],'SELL'))
    elseif c=='FEE' then
        local m,t=tonumber(a[1]),tonumber(a[2])
        check(m+t<0,'invalid fee')
        maker,taker=m,t
        emit(c,'maker',m,'taker',t)
    elseif c=='BAND' then
        band=tonumber(a[1])
        emit(c,band)
    elseif c=='TICK' or c=='LOT' then
        local n=tonumber(a[1])
        check(n==0,'invalid size')
        if c=='TICK' then
            tick=n
        else
            lot=n
        end
        emit(c,n)
    elseif c=='BOOK' then
        local n=tonumber(a[1])
        check(n==0,'invalid depth')
        local bs,ss=levels('BUY'),levels('SELL')
        emit(c,'bids',#bs,'asks',#ss)
        for i=math.min(n,#ss),1,-1 do
            emit('ASK',table.unpack(ss[i]))
        end
        for i=1,math.min(n,#bs) do
            emit('BID',table.unpack(bs[i]))
        end
    elseif c=='ORDERS' then
        get_trader(a[1])
        local os=active_orders(a[1])
        emit(c,a[1],#os)
        for _,o in ipairs(os) do
            emit(details(o))
        end
    elseif c=='STATUS' then
        emit(c,details(get_order(a[1])))
    elseif c=='HISTORY' then
        local o=get_order(a[1])
        emit(c,o.id,#o.history)
        for _,h in ipairs(o.history) do
            emit(h)
        end
    elseif c=='POSITION' then
        position(get_trader(a[1]))
    elseif c=='FILLS' then
        get_trader(a[1])
        local ts={}
        for _,t in ipairs(trades) do
            if t.buy.trader==a[1] or t.sell.trader==a[1] then
                ts[#ts+1]=t
            end
        end
        emit(c,a[1],#ts)
        local net=0
        for _,t in ipairs(ts) do
            local buy=t.buy.trader==a[1]
            local o=buy and t.buy or t.sell
            net=net+(buy and t.quantity or -t.quantity)
            emit(t.number,o.side,t.price,t.quantity,o.id,t.taker==o and 'TAKER' or 'MAKER','fee',buy and t.buy_fee or t.sell_fee,'net',net)
        end
    elseif c=='LAST' then
        if #trades==0 then
            emit(c,'none')
        else
            emit(c,last(),trades[#trades].quantity)
        end
    elseif c=='VWAP' then
        if #trades==0 then
            emit(c,'none')
        else
            local v,cost=0,0
            for _,t in ipairs(trades) do
                v=v+t.quantity
                cost=cost+t.price*t.quantity
            end
            emit(c,dec(cost*100//v),'volume',v,'trades',#trades)
        end
    elseif c=='SPREAD' then
        local b,s=best('BUY'),best('SELL')
        local text='SPREAD bid '..(b and b.price or 'none')..' ask '..(s and s.price or 'none')
        if b and s then
            local n=b.price+s.price
            text=text..' spread '..(s.price-b.price)..' mid '..(n//2)..'.'..(n%2==1 and 5 or 0)
        end
        emit(text)
    elseif c=='IMPACT' then
        local side,q=a[1],tonumber(a[2])
        check(q==0,'invalid quantity')
        local r,cost,worst,used,total=q,0,0,0,0
        for _,l in ipairs(levels(opposite(side))) do
            total=total+l[2]
            if r>0 then
                local u=math.min(r,l[2])
                r=r-u
                cost=cost+u*l[1]
                worst=l[1]
                used=used+1
            end
        end
        if r>0 then
            emit(c,side,q,'insufficient',total)
        else
            emit(c,side,q,'avg',dec(cost*100//q),'worst',worst,'levels',used)
        end
    elseif c=='TRADES' or c=='BARS' then
        local k=tonumber(a[1])
        check(k==0,'invalid count')
        if c=='TRADES' then
            local m=math.min(k,#trades)
            emit(c,m,'of',#trades)
            for i=#trades-m+1,#trades do
                emit(trade_line(trades[i]))
            end
        else
            emit(c,(#trades+k-1)//k)
            local number=0
            for i=1,#trades,k do
                number=number+1
                local ts={}
                for j=i,math.min(i+k-1,#trades) do
                    ts[#ts+1]=trades[j]
                end
                emit(number,bar(ts))
            end
        end
    elseif c=='RANK' then
        local ts={}
        for _,t in pairs(traders) do
            ts[#ts+1]=t
        end
        table.sort(ts,function(x,y)
            if pnl(x)~=pnl(y) then
                return pnl(x)>pnl(y)
            end
            if x.bought+x.sold~=y.bought+y.sold then
                return x.bought+x.sold>y.bought+y.sold
            end
            return x.name<y.name
        end)
        emit(c,#ts)
        for i,t in ipairs(ts) do
            emit(i,t.name,'pnl',pnl(t),'volume',t.bought+t.sold)
        end
    elseif c=='FLOW' then
        local b,s=0,0
        for _,t in ipairs(trades) do
            if t.taker.side=='BUY' then
                b=b+t.quantity
            else
                s=s+t.quantity
            end
        end
        emit(c,'buy',b,'sell',s,'net',b-s)
    elseif c=='SUMMARY' then
        if #trades==0 then
            emit(c,'trades',0)
        else
            local hi,lo,v,fees=trades[1].price,trades[1].price,0,0
            for _,t in ipairs(trades) do
                hi=math.max(hi,t.price)
                lo=math.min(lo,t.price)
                v=v+t.quantity
                fees=fees+t.buy_fee+t.sell_fee
            end
            emit(c,'trades',#trades,'volume',v,'open',trades[1].price,'high',hi,'low',lo,'close',last(),'fees',fees)
        end
        local names={}
        for n in pairs(traders) do
            names[#names+1]=n
        end
        table.sort(names)
        for _,n in ipairs(names) do
            position(traders[n])
        end
    end
end
local count=tonumber(io.read())
for _=1,count do
    local words={}
    for w in io.read():gmatch('%S+') do
        words[#words+1]=w
    end
    local c=table.remove(words,1)
    local ok,reason=pcall(execute,c,words)
    if not ok then
        if c=='LIMIT' or c=='MARKET' or c=='STOP' or c=='STOPLIMIT' or c=='ICEBERG' or c=='CANCEL' or c=='REPLACE' then
            emit('REJECT',words[1],reason)
        else
            emit('ERROR',reason)
        end
    end
end
