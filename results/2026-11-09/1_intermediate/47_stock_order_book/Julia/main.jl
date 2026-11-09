
mutable struct BookOrder
    id::String
    trader::String
    kind::String
    side::String
    condition::String
    status::String
    price::Int
    trigger::Int
    peak::Int
    quantity::Int
    remaining::Int
    visible::Int
    filled::Int
    value::Int
    priority::Int
    history::Vector{String}
end

mutable struct BookTrader
    bought::Int
    sold::Int
    cash::Int
    fees::Int
    limit::Union{Nothing, Int}
end

struct BookTrade
    price::Int
    quantity::Int
    buy::BookOrder
    sell::BookOrder
    taker::BookOrder
    bf::Int
    sf::Int
end

mutable struct MatchingEngine
    orders::Vector{BookOrder}
    ids::Dict{String, BookOrder}
    traders::Dict{String, BookTrader}
    trades::Vector{BookTrade}
    priority::Int
    maker::Int
    taker::Int
    band::Int
    tick::Int
    lot::Int
    halted::Bool
end

struct CommandError <: Exception
    reason::String
end
fail(s) = throw(CommandError(s))
emit(xs...) = println(join(xs, " "))
dec(n) = string(n÷100, ".", lpad(n%100, 2, '0'))
resting(o) = o.status in ("OPEN", "PARTIAL")
active(o) = resting(o) || o.status == "PENDING"
lastprice(e) = isempty(e.trades) ? 0 : e.trades[end].price
register(e, t) = get!(()->BookTrader(0, 0, 0, 0, nothing), e.traders, t)
matchable(o, p) = o.price == 0 || (o.side == "BUY" ? p <= o.price : p >= o.price)
triggered(o, p) = o.side == "BUY" ? p >= o.trigger : p <= o.trigger

function exposure(e, t, s, excluded = nothing)
    x = get(e.traders, t, nothing)
    n = isnothing(x) ? 0 : x.bought-x.sold
    (s == "BUY" ? n : -n)+sum((o.remaining for o in e.orders if o !== excluded && o.trader == t && o.side == s && active(o));
    init = 0)
end

function risk(e, t, s, q, excluded = nothing)
    x = get(e.traders, t, nothing)
    !isnothing(x) && !isnothing(x.limit) && exposure(e, t, s, excluded)+q>x.limit
end
outside(e, p) = e.band>0 && !isempty(e.trades) && abs(p-lastprice(e))>e.band

function book(e, s)
    sort([o for o in e.orders if resting(o) && o.side == s];
    by = o->(s == "BUY" ? -o.price : o.price, o.priority))
end
best(e, s) = let b = book(e, s)
    isempty(b) ? nothing : b[1]
end
orderline(o) = emit("ORDER", o.id, o.status, "$(o.filled)/$(o.quantity)")

function details(o)
    p = o.price == 0 ? "-" : string(o.price)
    a = o.filled == 0 ? "-" : dec(o.value*100÷o.filled)
    s = "$(o.id) $(o.trader) $(o.kind) $(o.side) $p $(o.status) $(o.filled)/$(o.quantity) avg $a"
    o.trigger>0 ? s*" trigger $(o.trigger)" : s
end

function showposition(e, t)
    x = e.traders[t]
    n = x.bought-x.sold
    emit("POSITION", t, "bought", x.bought, "sold", x.sold, "net", n, "cash", x.cash, "fees", x.fees, "pnl", x.cash+n*lastprice(e))
end
tradeline(e, i) = let x = e.trades[i]
    emit("TRADE", i, x.price, x.quantity, x.buy.id, x.buy.trader, x.sell.id, x.sell.trader)
end

function execute!(e, o)
    op = o.side == "BUY" ? "SELL" : "BUY"
    while o.remaining>0
        y = best(e, op)
        (isnothing(y) || !matchable(o, y.price)) && break
        if y.trader == o.trader
            emit("STP", y.id, y.remaining)
            push!(y.history, "STP $(y.remaining)")
            y.remaining = 0
            y.status = "CANCELLED"
            continue
        end
        q = min(o.remaining, y.visible)
        p = y.price
        tf = q*e.taker
        mf = q*e.maker
        b, s, bf, sf = o.side == "BUY" ? (o, y, tf, mf) : (y, o, mf, tf)
        push!(e.trades, BookTrade(p, q, b, s, o, bf, sf))
        i = length(e.trades)
        for x in (o, y)
            x.remaining -= q
            x.filled += q
            x.value += q*p
            push!(x.history, "FILL $i $p $q")
        end
        y.visible -= q
        bt = e.traders[b.trader]
        st = e.traders[s.trader]
        bt.bought += q
        bt.cash -= q*p+bf
        bt.fees += bf
        st.sold += q
        st.cash += q*p-sf
        st.fees += sf
        tradeline(e, i)
        if y.remaining == 0
            y.status = "FILLED"
        else
            y.status = "PARTIAL"
            if y.visible == 0
                e.priority += 1
                y.priority = e.priority
                y.visible = min(y.peak, y.remaining)
                h = y.remaining-y.visible
                push!(y.history, "REFRESH $(y.visible) $h")
                emit("REFRESH", y.id, y.visible, h)
            end
        end
    end
end

function post!(e, o, force = false)
    if o.remaining == 0
        o.status = "FILLED"
    elseif force || (o.kind == "LIMIT" && o.condition != "IOC") || o.kind in ("ICEBERG", "STOPLIMIT")
        e.priority += 1
        o.priority = e.priority
        o.visible = o.peak>0 ? min(o.peak, o.remaining) : o.remaining
        o.status = o.filled>0 ? "PARTIAL" : "OPEN"
        push!(o.history, "REST $(o.price) $(o.visible)")
    else
        push!(o.history, "EXPIRE $(o.remaining)")
        o.remaining = 0
        o.status = "CANCELLED"
    end
    orderline(o)
end

function stops!(e)
    while !isempty(e.trades)
        p = lastprice(e)
        selected = [o for o in e.orders if o.status == "PENDING" && triggered(o, p)]
        isempty(selected) && return
        for o in selected
            o.status = "TRIGGERING"
        end
        for o in selected
            emit("TRIGGER", o.id)
            push!(o.history, "TRIGGER")
            execute!(e, o)
            post!(e, o)
        end
    end
end

function cancel!(o)
    push!(o.history, "CANCEL $(o.remaining)")
    o.remaining = 0
    o.status = "CANCELLED"
    orderline(o)
end

function levels(e, s)
    d = Dict{Int, Tuple{Int, Int}}()
    for o in book(e, s)
        q, n = get(d, o.price, (0, 0))
        d[o.price] = (q+o.visible, n+1)
    end
    [(p, d[p]...) for p in sort(collect(keys(d));
    rev = s == "BUY")]
end

function command!(e, w)
    c = w[1]
    n(i) = parse(Int, w[i])
    if c in ("LIMIT", "MARKET", "STOP", "STOPLIMIT", "ICEBERG")
        p = r = k = 0
        condition = ""
        if c == "MARKET"
            q = n(5)
        elseif c == "STOP"
            r = n(5)
            q = n(6)
        elseif c == "STOPLIMIT"
            r = n(5)
            p = n(6)
            q = n(7)
        else
            p = n(5)
            q = n(6)
            if c == "ICEBERG"
                k = n(7)
            elseif length(w) == 7
                condition = w[7]
            end
        end
        o = BookOrder(w[2], w[3], c, w[4], condition, "ARRIVING", p, r, k, q, q, 0, 0, 0, 0, ["ACCEPT"])
        prices = c == "MARKET" ? Int[] : c == "STOP" ? [r] : c == "STOPLIMIT" ? [r, p] : [p]
        e.halted && fail("halted")
        haskey(e.ids, o.id) && fail("duplicate id")
        any(==(0), prices) && fail("invalid price")
        q == 0 && fail("invalid quantity")
        any(x->x%e.tick != 0, prices) && fail("invalid tick")
        q%e.lot != 0 && fail("invalid lot")
        r>0 && !isempty(e.trades) && triggered(o, lastprice(e)) && fail("invalid trigger")
        c == "ICEBERG" && (k == 0 || k>q || k%e.lot != 0) && fail("invalid peak")
        p>0 && outside(e, p) && fail("outside band")
        risk(e, o.trader, o.side, q) && fail("risk limit")
        b = book(e, o.side == "BUY" ? "SELL" : "BUY")
        condition == "POSTONLY" && !isempty(b) && matchable(o, b[1].price) && fail("would cross")
        condition == "FOK" && sum((x.remaining for x in b if x.trader != o.trader && matchable(o, x.price));
        init = 0)<q && fail("unfillable")
        register(e, o.trader)
        push!(e.orders, o)
        e.ids[o.id] = o
        if r>0
            o.status = "PENDING"
            orderline(o)
        else
            condition != "POSTONLY" && execute!(e, o)
            post!(e, o)
            stops!(e)
        end
        return
    end
    if c in ("CANCEL", "REPLACE", "STATUS", "HISTORY")
        c == "REPLACE" && e.halted && fail("halted")
        haskey(e.ids, w[2]) || fail("unknown order")
        o = e.ids[w[2]]
        if c == "STATUS"
            emit(c, details(o))
        elseif c == "HISTORY"
            emit(c, o.id, length(o.history))
            foreach(emit, o.history)
        elseif c == "CANCEL"
            active(o) || fail("not open")
            cancel!(o)
        else
            p = n(3)
            q = n(4)
            moved = p != o.price
            resting(o) || fail("not open")
            p == 0 && fail("invalid price")
            q == 0 && fail("invalid quantity")
            moved && p%e.tick != 0 && fail("invalid tick")
            q%e.lot != 0 && fail("invalid lot")
            !moved && q == o.remaining && fail("no change")
            moved && outside(e, p) && fail("outside band")
            q>o.remaining && risk(e, o.trader, o.side, q, o) && fail("risk limit")
            kept = !moved && q<o.remaining
            mode = kept ? "kept" : "lost"
            o.quantity = o.filled+q
            o.price = p
            o.remaining = q
            push!(o.history, "REPLACE $p $q $mode")
            emit(c, o.id, mode)
            if kept
                o.visible = min(o.visible, q)
                orderline(o)
            else
                o.status = "ARRIVING"
                execute!(e, o)
                post!(e, o, true)
                stops!(e)
            end
        end
        return
    end
    if c in ("CANCELALL", "ORDERS", "POSITION", "FILLS")
        t = w[2]
        haskey(e.traders, t) || fail("unknown trader")
        if c in ("CANCELALL", "ORDERS")
            a = [o for o in e.orders if o.trader == t && active(o)]
            emit(c, t, length(a))
            for o in a
                c == "CANCELALL" ? cancel!(o) : emit(details(o))
            end
        elseif c == "POSITION"
            showposition(e, t)
        else
            a = [i for i in eachindex(e.trades) if e.trades[i].buy.trader == t || e.trades[i].sell.trader == t]
            emit(c, t, length(a))
            net = 0
            for i in a
                x = e.trades[i]
                buy = x.buy.trader == t
                o = buy ? x.buy : x.sell
                net += buy ? x.quantity : -x.quantity
                emit(i, buy ? "BUY" : "SELL", x.price, x.quantity, o.id, x.taker === o ? "TAKER" : "MAKER", "fee", buy ? x.bf : x.sf, "net", net)
            end
        end
        return
    end
    if c == "HALT"
        e.halted && fail("already halted")
        e.halted = true
        emit(c)
    elseif c == "RESUME"
        !e.halted && fail("not halted")
        e.halted = false
        emit(c)
    elseif c == "RISK"
        t = w[2]
        m = n(3)
        register(e, t).limit = m
        emit(c, t, m, "exposure buy", exposure(e, t, "BUY"), "sell", exposure(e, t, "SELL"))
    elseif c == "FEE"
        a = n(2)
        b = n(3)
        a+b<0 && fail("invalid fee")
        e.maker = a
        e.taker = b
        emit(c, "maker", a, "taker", b)
    elseif c == "BAND"
        e.band = n(2)
        emit(c, e.band)
    elseif c in ("TICK", "LOT")
        u = n(2)
        u == 0 && fail("invalid size")
        c == "TICK" ? (e.tick = u) : (e.lot = u)
        emit(c, u)
    elseif c == "BOOK"
        k = n(2)
        k == 0 && fail("invalid depth")
        b = levels(e, "BUY")
        a = levels(e, "SELL")
        emit(c, "bids", length(b), "asks", length(a))
        for x in reverse(a[1:min(k, length(a))])
            emit("ASK", x...)
        end
        for x in b[1:min(k, length(b))]
            emit("BID", x...)
        end
    elseif c == "LAST"
        isempty(e.trades) ? emit(c, "none") : emit(c, e.trades[end].price, e.trades[end].quantity)
    elseif c == "VWAP"
        if isempty(e.trades)
            emit(c, "none")
        else
            v = sum(x.quantity for x in e.trades)
            a = sum(x.price*x.quantity for x in e.trades)
            emit(c, dec(a*100÷v), "volume", v, "trades", length(e.trades))
        end
    elseif c == "SPREAD"
        b = best(e, "BUY")
        a = best(e, "SELL")
        if isnothing(b) || isnothing(a)
            emit(c, "bid", isnothing(b) ? "none" : b.price, "ask", isnothing(a) ? "none" : a.price)
        else
            s = b.price+a.price
            emit(c, "bid", b.price, "ask", a.price, "spread", a.price-b.price, "mid", "$(s÷2).$(s%2*5)")
        end
    elseif c == "IMPACT"
        s = w[2]
        q = n(3)
        q == 0 && fail("invalid quantity")
        r = q
        cost = worst = used = total = 0
        for (p, v, _) in levels(e, s == "BUY" ? "SELL" : "BUY")
            total += v
            if r>0
                u = min(r, v)
                r -= u
                cost += u*p
                worst = p
                used += 1
            end
        end
        r>0 ? emit(c, s, q, "insufficient", total) : emit(c, s, q, "avg", dec(cost*100÷q), "worst", worst, "levels", used)
    elseif c in ("TRADES", "BARS")
        k = n(2)
        k == 0 && fail("invalid count")
        T = length(e.trades)
        if c == "TRADES"
            m = min(k, T)
            emit(c, m, "of", T)
            for i in T-m+1:T
                tradeline(e, i)
            end
        else
            emit(c, cld(T, k))
            for i in 1:k:T
                g = e.trades[i:min(i+k-1, T)]
                p = [x.price for x in g]
                emit((i-1)÷k+1, "open", p[1], "high", maximum(p), "low", minimum(p), "close", p[end], "volume", sum(x.quantity for x in g))
            end
        end
    elseif c == "RANK"
        pnl(t) = let x = e.traders[t]
            x.cash+(x.bought-x.sold)*lastprice(e)
        end
        names = sort(collect(keys(e.traders));
        by = t->(-pnl(t), -e.traders[t].bought-e.traders[t].sold, t))
        emit(c, length(names))
        for (i, t) in enumerate(names)
            x = e.traders[t]
            emit(i, t, "pnl", pnl(t), "volume", x.bought+x.sold)
        end
    elseif c == "FLOW"
        b = sum((x.quantity for x in e.trades if x.taker.side == "BUY");
        init = 0)
        s = sum((x.quantity for x in e.trades if x.taker.side == "SELL");
        init = 0)
        emit(c, "buy", b, "sell", s, "net", b-s)
    elseif c == "SUMMARY"
        if isempty(e.trades)
            emit(c, "trades", 0)
        else
            p = [x.price for x in e.trades]
            emit(c, "trades", length(p), "volume", sum(x.quantity for x in e.trades), "open", p[1], "high", maximum(p), "low", minimum(p), "close", p[end], "fees", sum(x.bf+x.sf for x in e.trades))
        end
        for t in sort(collect(keys(e.traders)))
            showposition(e, t)
        end
    end
end

function main()
    e = MatchingEngine(BookOrder[], Dict{String, BookOrder}(), Dict{String, BookTrader}(), BookTrade[], 0, 0, 0, 0, 1, 1, false)
    for _ in 1:parse(Int, readline())
        w = String.(split(readline()))
        try
            command!(e, w)
        catch err
            err isa CommandError || rethrow()
            w[1] in ("LIMIT", "MARKET", "STOP", "STOPLIMIT", "ICEBERG", "CANCEL", "REPLACE") ? emit("REJECT", w[2], err.reason) : emit("ERROR", err.reason)
        end
    end
end
main()
