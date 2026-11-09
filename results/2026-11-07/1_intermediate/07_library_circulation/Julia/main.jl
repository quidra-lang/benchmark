using Printf
const RULES = Dict("STUDENT"=>(3,14,25,1000,2,50),"STAFF"=>(10,28,10,2000,5,100))
Base.@kwdef mutable struct BookCopy
    isbn::String
    number::Int
    state::String = "AVAILABLE"
    member::String = ""
    start::Int = 0
    due::Int = 0
    renewals::Int = 0
    expiry::Int = 0
end
Base.@kwdef mutable struct Title
    id::String
    name::String
    price::Int
    copies::Vector{BookCopy} = BookCopy[]
    queue::Vector{String} = String[]
    borrowed::Int = 0
end
mutable struct ChargeItem
    day::Int
    kind::String
    isbn::String
    amount::Int
    unpaid::Int
end
Base.@kwdef mutable struct LibMember
    id::String
    kind::String
    name::String
    loans::Dict{String,BookCopy} = Dict{String,BookCopy}()
    holds::Dict{String,BookCopy} = Dict{String,BookCopy}()
    items::Vector{ChargeItem} = ChargeItem[]
    history::Vector{String} = String[]
end
const CURRENT_DAY = Ref(1)
const CLOSED_DAYS = Set{Int}()
const BOOKS = Dict{String,Title}()
const BOOK_ORDER = String[]
const MEMBERS = Dict{String,LibMember}()
const MEMBER_ORDER = String[]
const COUNTS = Dict(key=>0 for key in ("borrowed","returned","renewed","lost","FINE","FEE","PRICE","paid","waived"))
fail(message) = throw(ArgumentError(message))
function cents(text)
    whole,fraction = split(text,'.')
    return 100parse(Int,whole)+parse(Int,fraction)
end
money(value) = @sprintf("%d.%02d",div(value,100),mod(value,100))
function isbn(text)
    s = replace(text,"-"=>"")
    if occursin(r"^[0-9]{9}[0-9X]$",s)
        total = sum((11-i)*(s[i] == 'X' ? 10 : Int(s[i]-'0')) for i in 1:10)
        mod(total,11) == 0 || fail("invalid isbn")
        s = "978"*s[1:9]
        total = sum(Int(s[i]-'0')*(isodd(i) ? 1 : 3) for i in 1:12)
        return s*string(mod(10-mod(total,10),10))
    elseif occursin(r"^97[89][0-9]{10}$",s)
        total = sum(Int(s[i]-'0')*(isodd(i) ? 1 : 3) for i in 1:13)
        mod(total,10) == 0 && return s
    end
    fail("invalid isbn")
end
function get_member(id)
    haskey(MEMBERS,id) || fail("unknown member")
    return MEMBERS[id]
end
function get_book(text)
    id = isbn(text)
    haskey(BOOKS,id) || fail("unknown book")
    return BOOKS[id]
end
balance(m) = sum((item.unpaid for item in m.items);init=0)
holdings(b) = count(c -> c.state in ("AVAILABLE","LOANED","HOLD"),b.copies)
reservations(m) = length(m.holds)+count(b -> m.id in b.queue,values(BOOKS))
function open_day(date)
    while date in CLOSED_DAYS
        date += 1
    end
    return date
end
function late_fine(c)
    m = MEMBERS[c.member]
    late = max(0,CURRENT_DAY[]-c.due)
    return late,min(late*RULES[m.kind][3],RULES[m.kind][4])
end
function charge!(m,kind,id,amount)
    amount == 0 && return
    push!(m.items,ChargeItem(CURRENT_DAY[],kind,id,amount,amount))
    COUNTS[kind] += amount
end
function release_copy!(b,c,out)
    if isempty(b.queue)
        c.state = "AVAILABLE"
        return
    end
    id = popfirst!(b.queue)
    c.state = "HOLD"
    c.member = id
    c.expiry = open_day(CURRENT_DAY[]+3)
    MEMBERS[id].holds[b.id] = c
    push!(out,"HOLD $(b.id) copy $(c.number) $id until $(c.expiry)")
end
function end_loan!(b,c,result)
    m = MEMBERS[c.member]
    late,fine = late_fine(c)
    delete!(m.loans,b.id)
    charge!(m,"FINE",b.id,fine)
    push!(m.history,"$result $(b.id) copy $(c.number) from $(c.start) to $(CURRENT_DAY[]) late $late fine $(money(fine))")
    return m,late,fine
end
function lose_copy!(b,c,heading,out)
    m,late,fine = end_loan!(b,c,"LOST")
    m.history[end] *= " price $(money(b.price))"
    charge!(m,"PRICE",b.id,b.price)
    c.state = "LOST"
    COUNTS["lost"] += 1
    push!(out,"$heading $(m.id) $(b.id) copy $(c.number) late $late fine $(money(fine)) price $(money(b.price)) balance $(money(balance(m)))")
    if holdings(b) == 0
        for id in b.queue
            push!(out,"DROPPED $(b.id) $id")
        end
        empty!(b.queue)
    end
end
function renewal_reason(b,c)
    c.due < CURRENT_DAY[] && return "loan overdue"
    c.renewals == 2 && return "renewal limit"
    return isempty(b.queue) ? "" : "title reserved"
end
function renew_loan!(m,b,c)
    c.due = open_day(CURRENT_DAY[]+RULES[m.kind][2])
    c.renewals += 1
    COUNTS["renewed"] += 1
    return "RENEW $(m.id) $(b.id) copy $(c.number) due $(c.due) renewals $(c.renewals)"
end
sorted_copies(copies,date) = sort(collect(values(copies));by=c -> (getproperty(c,date),c.isbn))
function execute(line)
    t = String.(split(line,' '))
    cmd = t[1]
    out = String[]
    if cmd == "DAY"
        target = parse(Int,t[2])
        target > CURRENT_DAY[] || fail("invalid day")
        push!(out,"DAY $target")
        while CURRENT_DAY[] < target
            nextday = target+1
            for m in values(MEMBERS)
                for c in values(m.loans)
                    nextday = min(nextday,c.due+365)
                end
                for c in values(m.holds)
                    nextday = min(nextday,c.expiry+1)
                end
            end
            if nextday > target
                CURRENT_DAY[] = target
                break
            end
            CURRENT_DAY[] = nextday
            losses = BookCopy[]
            for id in MEMBER_ORDER
                m = MEMBERS[id]
                for key in sort(collect(keys(m.loans)))
                    c = m.loans[key]
                    c.due+365 <= CURRENT_DAY[] && push!(losses,c)
                end
            end
            for c in losses
                lose_copy!(BOOKS[c.isbn],c,"AUTOLOST",out)
            end
            expired = BookCopy[]
            for id in BOOK_ORDER
                for c in BOOKS[id].copies
                    c.state == "HOLD" && c.expiry < CURRENT_DAY[] && push!(expired,c)
                end
            end
            for c in expired
                b,m = BOOKS[c.isbn],MEMBERS[c.member]
                fee = RULES[m.kind][6]
                charge!(m,"FEE",b.id,fee)
                delete!(m.holds,b.id)
                push!(out,"EXPIRED $(b.id) copy $(c.number) $(m.id) fee $(money(fee))")
                release_copy!(b,c,out)
            end
        end
    elseif cmd == "CLOSED"
        date = parse(Int,t[2])
        date > CURRENT_DAY[] || fail("invalid day")
        date in CLOSED_DAYS && fail("already closed")
        push!(CLOSED_DAYS,date)
        push!(out,"CLOSED $date")
        for id in BOOK_ORDER
            for c in BOOKS[id].copies
                if c.state == "LOANED" && c.due == date
                    c.due = open_day(date)
                    push!(out,"MOVED $id copy $(c.number) $(c.member) due $(c.due)")
                elseif c.state == "HOLD" && c.expiry == date
                    c.expiry = open_day(date)
                    push!(out,"MOVED $id copy $(c.number) $(c.member) until $(c.expiry)")
                end
            end
        end
    elseif cmd == "ADDBOOK"
        id = isbn(t[2])
        name = join(t[5:end]," ")
        haskey(BOOKS,id) && BOOKS[id].name != name && fail("title mismatch")
        if !haskey(BOOKS,id)
            BOOKS[id] = Title(id=id,name=name,price=0)
            push!(BOOK_ORDER,id)
            sort!(BOOK_ORDER)
        end
        b = BOOKS[id]
        b.price = cents(t[4])
        added = BookCopy[]
        for i in 1:parse(Int,t[3])
            c = BookCopy(isbn=id,number=length(b.copies)+1)
            push!(b.copies,c)
            push!(added,c)
        end
        push!(out,"ADDBOOK $id added $(t[3]) total $(holdings(b))")
        for c in added
            release_copy!(b,c,out)
        end
    elseif cmd == "ADDMEMBER"
        haskey(MEMBERS,t[2]) && fail("duplicate member")
        haskey(RULES,t[3]) || fail("unknown type")
        m = LibMember(id=t[2],kind=t[3],name=join(t[4:end]," "))
        MEMBERS[m.id] = m
        push!(MEMBER_ORDER,m.id)
        sort!(MEMBER_ORDER)
        rule = RULES[m.kind]
        push!(out,"ADDMEMBER $(m.id) $(m.kind) loans $(rule[1]) days $(rule[2])")
    elseif cmd in ("BORROW","RETURN","RENEW","RESERVE","CANCEL","LOST")
        m = get_member(t[2])
        b = get_book(t[3])
        id = b.id
        loan,hold = get(m.loans,id,nothing),get(m.holds,id,nothing)
        rule = RULES[m.kind]
        if cmd == "BORROW"
            CURRENT_DAY[] in CLOSED_DAYS && fail("library closed")
            loan !== nothing && fail("already borrowed")
            balance(m) > 500 && fail("member blocked")
            any(c -> c.due < CURRENT_DAY[],values(m.loans)) && fail("overdue loans")
            length(m.loans) < rule[1] || fail("loan limit")
            chosen = hold
            if chosen === nothing
                index = findfirst(c -> c.state == "AVAILABLE",b.copies)
                index !== nothing && (chosen = b.copies[index])
            end
            if chosen === nothing
                any(c -> c.state == "HOLD",b.copies) && fail("all copies on hold")
                fail("no copy available")
            end
            delete!(m.holds,id)
            chosen.state,chosen.member = "LOANED",m.id
            chosen.start = CURRENT_DAY[]
            chosen.due = open_day(CURRENT_DAY[]+rule[2])
            chosen.renewals = 0
            m.loans[id] = chosen
            b.borrowed += 1
            COUNTS["borrowed"] += 1
            push!(out,"BORROW $(m.id) $id copy $(chosen.number) due $(chosen.due)")
        elseif cmd in ("RETURN","RENEW","LOST")
            loan !== nothing || fail("not borrowed")
            if cmd == "RETURN"
                member,late,fine = end_loan!(b,loan,"RETURNED")
                COUNTS["returned"] += 1
                push!(out,"RETURN $(m.id) $id copy $(loan.number) late $late fine $(money(fine)) balance $(money(balance(m)))")
                release_copy!(b,loan,out)
            elseif cmd == "LOST"
                lose_copy!(b,loan,"LOST",out)
            else
                balance(m) > 500 && fail("member blocked")
                reason = renewal_reason(b,loan)
                isempty(reason) || fail(reason)
                push!(out,renew_loan!(m,b,loan))
            end
        elseif cmd == "RESERVE"
            loan !== nothing && fail("already borrowed")
            (hold !== nothing || m.id in b.queue) && fail("already reserved")
            balance(m) > 500 && fail("member blocked")
            reservations(m) < rule[5] || fail("reservation limit")
            holdings(b) > 0 || fail("no copies")
            any(c -> c.state == "AVAILABLE",b.copies) && fail("copy available")
            push!(b.queue,m.id)
            position = length(b.queue)
            dues = sort([c.due for c in b.copies if c.state == "LOANED"])
            estimate = position <= length(dues) ? string(dues[position]) : "none"
            push!(out,"RESERVE $(m.id) $id position $position estimate $estimate")
        else
            position = findfirst(==(m.id),b.queue)
            position !== nothing || hold !== nothing || fail("not reserved")
            if position !== nothing
                deleteat!(b.queue,position)
                push!(out,"CANCEL $(m.id) $id queue")
            else
                delete!(m.holds,id)
                push!(out,"CANCEL $(m.id) $id hold copy $(hold.number)")
                release_copy!(b,hold,out)
            end
        end
    elseif cmd in ("RENEWALL","PAYFINE","WAIVE","FINES","MEMBER","HISTORY")
        m = get_member(t[2])
        if cmd == "RENEWALL"
            isempty(m.loans) && fail("no loans")
            balance(m) > 500 && fail("member blocked")
            renewed,skipped = 0,0
            for id in sort(collect(keys(m.loans)))
                reason = renewal_reason(BOOKS[id],m.loans[id])
                if isempty(reason)
                    push!(out,renew_loan!(m,BOOKS[id],m.loans[id]))
                    renewed += 1
                else
                    push!(out,"SKIP $id $reason")
                    skipped += 1
                end
            end
            push!(out,"RENEWALL $(m.id) renewed $renewed skipped $skipped")
        elseif cmd == "PAYFINE"
            balance(m) > 0 || fail("no fines")
            remaining,paid = cents(t[3]),0
            lines = String[]
            for (index,item) in enumerate(m.items)
                applied = min(remaining,item.unpaid)
                if applied > 0
                    item.unpaid -= applied
                    remaining -= applied
                    paid += applied
                    push!(lines,"ITEM $index $(item.kind) paid $(money(applied)) remaining $(money(item.unpaid))")
                end
            end
            COUNTS["paid"] += paid
            push!(out,"PAYFINE $(m.id) paid $(money(paid)) change $(money(remaining)) balance $(money(balance(m)))")
            append!(out,lines)
        elseif cmd == "WAIVE"
            index = parse(Int,t[3])
            1 <= index <= length(m.items) || fail("unknown item")
            item = m.items[index]
            item.unpaid > 0 || fail("item settled")
            amount = item.unpaid
            item.unpaid = 0
            COUNTS["waived"] += amount
            push!(out,"WAIVE $(m.id) item $index $(item.kind) amount $(money(amount)) balance $(money(balance(m)))")
        elseif cmd == "FINES"
            n = count(item -> item.unpaid > 0,m.items)
            push!(out,"FINES $(m.id) items $n balance $(money(balance(m)))")
            for (index,item) in enumerate(m.items)
                item.unpaid > 0 && push!(out,"$index day $(item.day) $(item.kind) $(item.isbn) amount $(money(item.amount)) remaining $(money(item.unpaid))")
            end
        elseif cmd == "HISTORY"
            push!(out,"HISTORY $(m.id) $(length(m.history))")
            append!(out,m.history)
        else
            rule = RULES[m.kind]
            state = balance(m) > 500 ? "BLOCKED" : "OK"
            push!(out,"MEMBER $(m.id) $(m.kind) $(m.name)")
            push!(out,"STATUS loans $(length(m.loans))/$(rule[1]) reservations $(reservations(m))/$(rule[5]) balance $(money(balance(m))) $state")
            for c in sorted_copies(m.loans,:due)
                text = "LOAN $(c.isbn) copy $(c.number) due $(c.due) renewals $(c.renewals)"
                if c.due < CURRENT_DAY[]
                    late,fine = late_fine(c)
                    text *= " late $late fine $(money(fine))"
                end
                push!(out,text)
            end
            for c in sorted_copies(m.holds,:expiry)
                push!(out,"HOLD $(c.isbn) copy $(c.number) until $(c.expiry)")
            end
            for id in BOOK_ORDER
                position = findfirst(==(m.id),BOOKS[id].queue)
                position !== nothing && push!(out,"QUEUE $id position $position")
            end
        end
    elseif cmd in ("WITHDRAW","BOOK")
        b = get_book(t[2])
        if cmd == "WITHDRAW"
            index = parse(Int,t[3])
            1 <= index <= length(b.copies) || fail("unknown copy")
            c = b.copies[index]
            c.state == "AVAILABLE" || fail("copy not available")
            c.state = "WITHDRAWN"
            push!(out,"WITHDRAW $(b.id) copy $(c.number) total $(holdings(b))")
        else
            push!(out,"BOOK $(b.id) $(b.name)")
            push!(out,"PRICE $(money(b.price)) copies $(holdings(b)) borrowed $(b.borrowed)")
            for c in b.copies
                text = "COPY $(c.number) $(c.state)"
                if c.state == "LOANED"
                    text *= " $(c.member) due $(c.due)"
                elseif c.state == "HOLD"
                    text *= " $(c.member) until $(c.expiry)"
                end
                push!(out,text)
            end
            push!(out,join(vcat(["QUEUE",string(length(b.queue))],b.queue)," "))
        end
    elseif cmd == "SEARCH"
        keyword = lowercase(join(t[2:end]," "))
        found = filter(b -> occursin(keyword,lowercase(b.name)),collect(values(BOOKS)))
        sort!(found;by=b -> (lowercase(b.name),b.id))
        push!(out,"SEARCH $(length(found))")
        for b in found
            available = count(c -> c.state == "AVAILABLE",b.copies)
            push!(out,"$(b.id) $available/$(holdings(b)) $(b.name)")
        end
    elseif cmd in ("OVERDUE","NOTICES")
        lines = String[]
        if cmd == "OVERDUE"
            loans = [c for m in values(MEMBERS) for c in values(m.loans) if c.due < CURRENT_DAY[]]
            sort!(loans;by=c -> (c.due,c.member,c.isbn))
            for c in loans
                late,fine = late_fine(c)
                push!(lines,"$(c.member) $(c.isbn) copy $(c.number) due $(c.due) late $late fine $(money(fine))")
            end
        else
            for id in MEMBER_ORDER
                m = MEMBERS[id]
                loans = sorted_copies(m.loans,:due)
                for c in loans
                    c.due < CURRENT_DAY[] && push!(lines,"OVERDUE $id $(c.isbn) due $(c.due)")
                end
                for c in loans
                    CURRENT_DAY[] <= c.due <= CURRENT_DAY[]+2 && push!(lines,"DUESOON $id $(c.isbn) due $(c.due)")
                end
                for c in sorted_copies(m.holds,:expiry)
                    push!(lines,"PICKUP $id $(c.isbn) until $(c.expiry)")
                end
            end
        end
        push!(out,"$cmd $(length(lines))")
        append!(out,lines)
    elseif cmd == "MEMBERS"
        push!(out,"MEMBERS $(length(MEMBERS))")
        for id in MEMBER_ORDER
            m = MEMBERS[id]
            state = balance(m) > 500 ? "BLOCKED" : "OK"
            push!(out,"$id $(m.kind) loans $(length(m.loans)) reservations $(reservations(m)) balance $(money(balance(m))) $state")
        end
    elseif cmd == "INVENTORY"
        totals = Dict(state=>0 for state in ("AVAILABLE","LOANED","HOLD","LOST","WITHDRAWN"))
        lines = String[]
        for id in BOOK_ORDER
            b = BOOKS[id]
            n = Dict(state=>0 for state in keys(totals))
            for c in b.copies
                n[c.state] += 1
            end
            for (state,total) in n
                totals[state] += total
            end
            push!(lines,"$id copies $(holdings(b)) available $(n["AVAILABLE"]) loaned $(n["LOANED"]) hold $(n["HOLD"]) queue $(length(b.queue))")
        end
        holding = totals["AVAILABLE"]+totals["LOANED"]+totals["HOLD"]
        push!(out,"INVENTORY titles $(length(BOOKS)) copies $holding available $(totals["AVAILABLE"]) loaned $(totals["LOANED"]) hold $(totals["HOLD"]) lost $(totals["LOST"]) withdrawn $(totals["WITHDRAWN"])")
        append!(out,lines)
    elseif cmd == "STATS"
        active = sum((length(m.loans) for m in values(MEMBERS));init=0)
        outstanding = sum((balance(m) for m in values(MEMBERS));init=0)
        push!(out,"STATS day $(CURRENT_DAY[]) titles $(length(BOOKS)) members $(length(MEMBERS)) closed $(length(CLOSED_DAYS))")
        push!(out,"LOANS borrowed $(COUNTS["borrowed"]) returned $(COUNTS["returned"]) renewed $(COUNTS["renewed"]) lost $(COUNTS["lost"]) active $active")
        push!(out,"MONEY fines $(money(COUNTS["FINE"])) fees $(money(COUNTS["FEE"])) charges $(money(COUNTS["PRICE"])) paid $(money(COUNTS["paid"])) waived $(money(COUNTS["waived"])) outstanding $(money(outstanding))")
        top = sort(filter(b -> b.borrowed > 0,collect(values(BOOKS)));by=b -> (-b.borrowed,b.id))
        for (rank,b) in enumerate(top[1:min(3,length(top))])
            push!(out,"TOP $rank $(b.id) $(b.borrowed) $(b.name)")
        end
    end
    return out
end
function main()
    for i in 1:parse(Int,readline())
        line = readline()
        try
            foreach(println,execute(line))
        catch exception
            exception isa ArgumentError || rethrow()
            println("ERROR ",exception.msg)
        end
    end
end
main()
