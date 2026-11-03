local RULES = {STUDENT={3,14,25,1000,2,50},STAFF={10,28,10,2000,5,100}}
local books,members,closed = {},{},{}
local book_order,member_order = {},{}
local day = 1
local counts = {borrowed=0,returned=0,renewed=0,lost=0,FINE=0,FEE=0,PRICE=0,paid=0,waived=0}
local function fail(message) error(message,0) end
local function size(map)
    local total = 0
    for _ in pairs(map) do total = total+1 end
    return total
end
local function keys(map)
    local values = {}
    for key in pairs(map) do values[#values+1] = key end
    table.sort(values)
    return values
end
local function append(target,items)
    table.move(items,1,#items,#target+1,target)
end
local function find(values,needle)
    for index,value in ipairs(values) do
        if value == needle then return index end
    end
    return nil
end
local function cents(text)
    local whole,fraction = text:match('^(%d+)%.(%d%d)$')
    return tonumber(whole)*100+tonumber(fraction)
end
local function money(value) return string.format('%d.%02d',value//100,value%100) end
local function isbn(text)
    local s = text:gsub('-','')
    if #s == 10 and s:match('^[0-9]+[0-9X]$') and s:sub(1,9):match('^[0-9]+$') then
        local total = 0
        for index = 1,10 do
            local char = s:sub(index,index)
            total = total+(11-index)*(char == 'X' and 10 or tonumber(char))
        end
        if total%11 ~= 0 then fail('invalid isbn') end
        s = '978' .. s:sub(1,9)
        total = 0
        for index = 1,12 do total = total+tonumber(s:sub(index,index))*(index%2 == 1 and 1 or 3) end
        return s .. ((10-total%10)%10)
    end
    if #s == 13 and s:match('^[0-9]+$') and (s:sub(1,3) == '978' or s:sub(1,3) == '979') then
        local total = 0
        for index = 1,13 do total = total+tonumber(s:sub(index,index))*(index%2 == 1 and 1 or 3) end
        if total%10 == 0 then return s end
    end
    fail('invalid isbn')
end
local function get_member(id)
    if not members[id] then fail('unknown member') end
    return members[id]
end
local function get_book(text)
    local id = isbn(text)
    if not books[id] then fail('unknown book') end
    return books[id]
end
local function balance(m)
    local total = 0
    for _,item in ipairs(m.items) do total = total+item.unpaid end
    return total
end
local function holdings(b)
    local total = 0
    for _,c in ipairs(b.copies) do
        if c.state == 'AVAILABLE' or c.state == 'LOANED' or c.state == 'HOLD' then total = total+1 end
    end
    return total
end
local function reservations(m)
    local total = size(m.holds)
    for _,id in ipairs(book_order) do
        if find(books[id].queue,m.id) then total = total+1 end
    end
    return total
end
local function open_day(date)
    while closed[date] do date = date+1 end
    return date
end
local function late_fine(c)
    local m = members[c.member]
    local late = math.max(0,day-c.due)
    return late,math.min(late*RULES[m.type][3],RULES[m.type][4])
end
local function charge(m,kind,id,amount)
    if amount == 0 then return end
    m.items[#m.items+1] = {day=day,kind=kind,isbn=id,amount=amount,unpaid=amount}
    counts[kind] = counts[kind]+amount
end
local function release_copy(b,c,out)
    if #b.queue == 0 then
        c.state = 'AVAILABLE'
        return
    end
    local id = table.remove(b.queue,1)
    c.state,c.member,c.expiry = 'HOLD',id,open_day(day+3)
    members[id].holds[b.id] = c
    out[#out+1] = 'HOLD ' .. b.id .. ' copy ' .. c.number .. ' ' .. id .. ' until ' .. c.expiry
end
local function end_loan(b,c,result)
    local m = members[c.member]
    local late,fine = late_fine(c)
    m.loans[b.id] = nil
    charge(m,'FINE',b.id,fine)
    m.history[#m.history+1] = result .. ' ' .. b.id .. ' copy ' .. c.number .. ' from ' .. c.start .. ' to ' .. day .. ' late ' .. late .. ' fine ' .. money(fine)
    return m,late,fine
end
local function lose_copy(b,c,heading,out)
    local m,late,fine = end_loan(b,c,'LOST')
    m.history[#m.history] = m.history[#m.history] .. ' price ' .. money(b.price)
    charge(m,'PRICE',b.id,b.price)
    c.state = 'LOST'
    counts.lost = counts.lost+1
    out[#out+1] = heading .. ' ' .. m.id .. ' ' .. b.id .. ' copy ' .. c.number .. ' late ' .. late .. ' fine ' .. money(fine) .. ' price ' .. money(b.price) .. ' balance ' .. money(balance(m))
    if holdings(b) == 0 then
        for _,id in ipairs(b.queue) do out[#out+1] = 'DROPPED ' .. b.id .. ' ' .. id end
        b.queue = {}
    end
end
local function renewal_reason(b,c)
    if c.due < day then return 'loan overdue' end
    if c.renewals == 2 then return 'renewal limit' end
    return #b.queue > 0 and 'title reserved' or ''
end
local function renew_loan(m,b,c)
    c.due = open_day(day+RULES[m.type][2])
    c.renewals = c.renewals+1
    counts.renewed = counts.renewed+1
    return 'RENEW ' .. m.id .. ' ' .. b.id .. ' copy ' .. c.number .. ' due ' .. c.due .. ' renewals ' .. c.renewals
end
local function sorted_copies(map,date)
    local copies = {}
    for _,c in pairs(map) do copies[#copies+1] = c end
    table.sort(copies,function(a,b)
        if a[date] ~= b[date] then return a[date] < b[date] end
        return a.isbn < b.isbn
    end)
    return copies
end
local function execute(line)
    local t,out = {},{}
    for token in line:gmatch('%S+') do t[#t+1] = token end
    local cmd = t[1]
    local function emit(text) out[#out+1] = text end
    if cmd == 'DAY' then
        local target = tonumber(t[2])
        if target <= day then fail('invalid day') end
        emit('DAY ' .. target)
        while day < target do
            local next_day = target+1
            for _,m in pairs(members) do
                for _,c in pairs(m.loans) do next_day = math.min(next_day,c.due+365) end
                for _,c in pairs(m.holds) do next_day = math.min(next_day,c.expiry+1) end
            end
            if next_day > target then
                day = target
                break
            end
            day = next_day
            local losses = {}
            for _,id in ipairs(member_order) do
                local m = members[id]
                for _,key in ipairs(keys(m.loans)) do
                    local c = m.loans[key]
                    if c.due+365 <= day then losses[#losses+1] = c end
                end
            end
            for _,c in ipairs(losses) do lose_copy(books[c.isbn],c,'AUTOLOST',out) end
            local expired = {}
            for _,id in ipairs(book_order) do
                for _,c in ipairs(books[id].copies) do
                    if c.state == 'HOLD' and c.expiry < day then expired[#expired+1] = c end
                end
            end
            for _,c in ipairs(expired) do
                local b,m = books[c.isbn],members[c.member]
                local fee = RULES[m.type][6]
                charge(m,'FEE',b.id,fee)
                m.holds[b.id] = nil
                emit('EXPIRED ' .. b.id .. ' copy ' .. c.number .. ' ' .. m.id .. ' fee ' .. money(fee))
                release_copy(b,c,out)
            end
        end
    elseif cmd == 'CLOSED' then
        local date = tonumber(t[2])
        if date <= day then fail('invalid day') end
        if closed[date] then fail('already closed') end
        closed[date] = true
        emit('CLOSED ' .. date)
        for _,id in ipairs(book_order) do
            for _,c in ipairs(books[id].copies) do
                if c.state == 'LOANED' and c.due == date then
                    c.due = open_day(date)
                    emit('MOVED ' .. id .. ' copy ' .. c.number .. ' ' .. c.member .. ' due ' .. c.due)
                elseif c.state == 'HOLD' and c.expiry == date then
                    c.expiry = open_day(date)
                    emit('MOVED ' .. id .. ' copy ' .. c.number .. ' ' .. c.member .. ' until ' .. c.expiry)
                end
            end
        end
    elseif cmd == 'ADDBOOK' then
        local id,name = isbn(t[2]),table.concat(t,' ',5)
        if books[id] and books[id].name ~= name then fail('title mismatch') end
        if not books[id] then
            books[id] = {id=id,name=name,price=0,copies={},queue={},borrowed=0}
            book_order[#book_order+1] = id
            table.sort(book_order)
        end
        local b,added = books[id],{}
        b.price = cents(t[4])
        for _ = 1,tonumber(t[3]) do
            local c = {isbn=id,number=#b.copies+1,state='AVAILABLE',member='',start=0,due=0,renewals=0,expiry=0}
            b.copies[#b.copies+1] = c
            added[#added+1] = c
        end
        emit('ADDBOOK ' .. id .. ' added ' .. t[3] .. ' total ' .. holdings(b))
        for _,c in ipairs(added) do release_copy(b,c,out) end
    elseif cmd == 'ADDMEMBER' then
        if members[t[2]] then fail('duplicate member') end
        if not RULES[t[3]] then fail('unknown type') end
        local m = {id=t[2],type=t[3],name=table.concat(t,' ',4),loans={},holds={},items={},history={}}
        members[m.id] = m
        member_order[#member_order+1] = m.id
        table.sort(member_order)
        local rule = RULES[m.type]
        emit('ADDMEMBER ' .. m.id .. ' ' .. m.type .. ' loans ' .. rule[1] .. ' days ' .. rule[2])
    elseif cmd == 'BORROW' or cmd == 'RETURN' or cmd == 'RENEW' or cmd == 'RESERVE' or cmd == 'CANCEL' or cmd == 'LOST' then
        local m = get_member(t[2])
        local b = get_book(t[3])
        local id,rule = b.id,RULES[m.type]
        local loan,hold = m.loans[id],m.holds[id]
        if cmd == 'BORROW' then
            if closed[day] then fail('library closed') end
            if loan then fail('already borrowed') end
            if balance(m) > 500 then fail('member blocked') end
            for _,c in pairs(m.loans) do
                if c.due < day then fail('overdue loans') end
            end
            if size(m.loans) >= rule[1] then fail('loan limit') end
            local chosen = hold
            if not chosen then
                for _,c in ipairs(b.copies) do
                    if c.state == 'AVAILABLE' then
                        chosen = c
                        break
                    end
                end
            end
            if not chosen then
                for _,c in ipairs(b.copies) do
                    if c.state == 'HOLD' then fail('all copies on hold') end
                end
                fail('no copy available')
            end
            m.holds[id] = nil
            chosen.state,chosen.member,chosen.start = 'LOANED',m.id,day
            chosen.due,chosen.renewals = open_day(day+rule[2]),0
            m.loans[id] = chosen
            b.borrowed,counts.borrowed = b.borrowed+1,counts.borrowed+1
            emit('BORROW ' .. m.id .. ' ' .. id .. ' copy ' .. chosen.number .. ' due ' .. chosen.due)
        elseif cmd == 'RETURN' or cmd == 'RENEW' or cmd == 'LOST' then
            if not loan then fail('not borrowed') end
            if cmd == 'RETURN' then
                local _,late,fine = end_loan(b,loan,'RETURNED')
                counts.returned = counts.returned+1
                emit('RETURN ' .. m.id .. ' ' .. id .. ' copy ' .. loan.number .. ' late ' .. late .. ' fine ' .. money(fine) .. ' balance ' .. money(balance(m)))
                release_copy(b,loan,out)
            elseif cmd == 'LOST' then
                lose_copy(b,loan,'LOST',out)
            else
                if balance(m) > 500 then fail('member blocked') end
                local reason = renewal_reason(b,loan)
                if reason ~= '' then fail(reason) end
                emit(renew_loan(m,b,loan))
            end
        elseif cmd == 'RESERVE' then
            if loan then fail('already borrowed') end
            if hold or find(b.queue,m.id) then fail('already reserved') end
            if balance(m) > 500 then fail('member blocked') end
            if reservations(m) >= rule[5] then fail('reservation limit') end
            if holdings(b) == 0 then fail('no copies') end
            for _,c in ipairs(b.copies) do
                if c.state == 'AVAILABLE' then fail('copy available') end
            end
            b.queue[#b.queue+1] = m.id
            local position,dues = #b.queue,{}
            for _,c in ipairs(b.copies) do
                if c.state == 'LOANED' then dues[#dues+1] = c.due end
            end
            table.sort(dues)
            emit('RESERVE ' .. m.id .. ' ' .. id .. ' position ' .. position .. ' estimate ' .. (dues[position] or 'none'))
        else
            local position = find(b.queue,m.id)
            if not position and not hold then fail('not reserved') end
            if position then
                table.remove(b.queue,position)
                emit('CANCEL ' .. m.id .. ' ' .. id .. ' queue')
            else
                m.holds[id] = nil
                emit('CANCEL ' .. m.id .. ' ' .. id .. ' hold copy ' .. hold.number)
                release_copy(b,hold,out)
            end
        end
    elseif cmd == 'RENEWALL' or cmd == 'PAYFINE' or cmd == 'WAIVE' or cmd == 'FINES' or cmd == 'MEMBER' or cmd == 'HISTORY' then
        local m = get_member(t[2])
        if cmd == 'RENEWALL' then
            if size(m.loans) == 0 then fail('no loans') end
            if balance(m) > 500 then fail('member blocked') end
            local renewed,skipped = 0,0
            for _,id in ipairs(keys(m.loans)) do
                local reason = renewal_reason(books[id],m.loans[id])
                if reason == '' then
                    emit(renew_loan(m,books[id],m.loans[id]))
                    renewed = renewed+1
                else
                    emit('SKIP ' .. id .. ' ' .. reason)
                    skipped = skipped+1
                end
            end
            emit('RENEWALL ' .. m.id .. ' renewed ' .. renewed .. ' skipped ' .. skipped)
        elseif cmd == 'PAYFINE' then
            if balance(m) == 0 then fail('no fines') end
            local remaining,paid,lines = cents(t[3]),0,{}
            for index,item in ipairs(m.items) do
                local applied = math.min(remaining,item.unpaid)
                if applied > 0 then
                    item.unpaid,remaining,paid = item.unpaid-applied,remaining-applied,paid+applied
                    lines[#lines+1] = 'ITEM ' .. index .. ' ' .. item.kind .. ' paid ' .. money(applied) .. ' remaining ' .. money(item.unpaid)
                end
            end
            counts.paid = counts.paid+paid
            emit('PAYFINE ' .. m.id .. ' paid ' .. money(paid) .. ' change ' .. money(remaining) .. ' balance ' .. money(balance(m)))
            append(out,lines)
        elseif cmd == 'WAIVE' then
            local index = tonumber(t[3])
            local item = m.items[index]
            if not item then fail('unknown item') end
            if item.unpaid == 0 then fail('item settled') end
            local amount = item.unpaid
            item.unpaid = 0
            counts.waived = counts.waived+amount
            emit('WAIVE ' .. m.id .. ' item ' .. index .. ' ' .. item.kind .. ' amount ' .. money(amount) .. ' balance ' .. money(balance(m)))
        elseif cmd == 'FINES' then
            local count = 0
            for _,item in ipairs(m.items) do
                if item.unpaid > 0 then count = count+1 end
            end
            emit('FINES ' .. m.id .. ' items ' .. count .. ' balance ' .. money(balance(m)))
            for index,item in ipairs(m.items) do
                if item.unpaid > 0 then emit(index .. ' day ' .. item.day .. ' ' .. item.kind .. ' ' .. item.isbn .. ' amount ' .. money(item.amount) .. ' remaining ' .. money(item.unpaid)) end
            end
        elseif cmd == 'HISTORY' then
            emit('HISTORY ' .. m.id .. ' ' .. #m.history)
            append(out,m.history)
        else
            local rule = RULES[m.type]
            local state = balance(m) > 500 and 'BLOCKED' or 'OK'
            emit('MEMBER ' .. m.id .. ' ' .. m.type .. ' ' .. m.name)
            emit('STATUS loans ' .. size(m.loans) .. '/' .. rule[1] .. ' reservations ' .. reservations(m) .. '/' .. rule[5] .. ' balance ' .. money(balance(m)) .. ' ' .. state)
            for _,c in ipairs(sorted_copies(m.loans,'due')) do
                local text = 'LOAN ' .. c.isbn .. ' copy ' .. c.number .. ' due ' .. c.due .. ' renewals ' .. c.renewals
                if c.due < day then
                    local late,fine = late_fine(c)
                    text = text .. ' late ' .. late .. ' fine ' .. money(fine)
                end
                emit(text)
            end
            for _,c in ipairs(sorted_copies(m.holds,'expiry')) do emit('HOLD ' .. c.isbn .. ' copy ' .. c.number .. ' until ' .. c.expiry) end
            for _,id in ipairs(book_order) do
                local position = find(books[id].queue,m.id)
                if position then emit('QUEUE ' .. id .. ' position ' .. position) end
            end
        end
    elseif cmd == 'WITHDRAW' or cmd == 'BOOK' then
        local b = get_book(t[2])
        if cmd == 'WITHDRAW' then
            local c = b.copies[tonumber(t[3])]
            if not c then fail('unknown copy') end
            if c.state ~= 'AVAILABLE' then fail('copy not available') end
            c.state = 'WITHDRAWN'
            emit('WITHDRAW ' .. b.id .. ' copy ' .. c.number .. ' total ' .. holdings(b))
        else
            emit('BOOK ' .. b.id .. ' ' .. b.name)
            emit('PRICE ' .. money(b.price) .. ' copies ' .. holdings(b) .. ' borrowed ' .. b.borrowed)
            for _,c in ipairs(b.copies) do
                local text = 'COPY ' .. c.number .. ' ' .. c.state
                if c.state == 'LOANED' then text = text .. ' ' .. c.member .. ' due ' .. c.due
                elseif c.state == 'HOLD' then text = text .. ' ' .. c.member .. ' until ' .. c.expiry end
                emit(text)
            end
            local parts = {'QUEUE',#b.queue}
            append(parts,b.queue)
            emit(table.concat(parts,' '))
        end
    elseif cmd == 'SEARCH' then
        local keyword = table.concat(t,' ',2):lower()
        local found = {}
        for _,b in pairs(books) do
            if b.name:lower():find(keyword,1,true) then found[#found+1] = b end
        end
        table.sort(found,function(a,b)
            if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end
            return a.id < b.id
        end)
        emit('SEARCH ' .. #found)
        for _,b in ipairs(found) do
            local available = 0
            for _,c in ipairs(b.copies) do
                if c.state == 'AVAILABLE' then available = available+1 end
            end
            emit(b.id .. ' ' .. available .. '/' .. holdings(b) .. ' ' .. b.name)
        end
    elseif cmd == 'OVERDUE' or cmd == 'NOTICES' then
        local lines = {}
        if cmd == 'OVERDUE' then
            local loans = {}
            for _,m in pairs(members) do
                for _,c in pairs(m.loans) do
                    if c.due < day then loans[#loans+1] = c end
                end
            end
            table.sort(loans,function(a,b)
                if a.due ~= b.due then return a.due < b.due end
                if a.member ~= b.member then return a.member < b.member end
                return a.isbn < b.isbn
            end)
            for _,c in ipairs(loans) do
                local late,fine = late_fine(c)
                lines[#lines+1] = c.member .. ' ' .. c.isbn .. ' copy ' .. c.number .. ' due ' .. c.due .. ' late ' .. late .. ' fine ' .. money(fine)
            end
        else
            for _,id in ipairs(member_order) do
                local m = members[id]
                local loans = sorted_copies(m.loans,'due')
                for _,c in ipairs(loans) do
                    if c.due < day then lines[#lines+1] = 'OVERDUE ' .. id .. ' ' .. c.isbn .. ' due ' .. c.due end
                end
                for _,c in ipairs(loans) do
                    if c.due >= day and c.due <= day+2 then lines[#lines+1] = 'DUESOON ' .. id .. ' ' .. c.isbn .. ' due ' .. c.due end
                end
                for _,c in ipairs(sorted_copies(m.holds,'expiry')) do lines[#lines+1] = 'PICKUP ' .. id .. ' ' .. c.isbn .. ' until ' .. c.expiry end
            end
        end
        emit(cmd .. ' ' .. #lines)
        append(out,lines)
    elseif cmd == 'MEMBERS' then
        emit('MEMBERS ' .. #member_order)
        for _,id in ipairs(member_order) do
            local m = members[id]
            emit(id .. ' ' .. m.type .. ' loans ' .. size(m.loans) .. ' reservations ' .. reservations(m) .. ' balance ' .. money(balance(m)) .. ' ' .. (balance(m) > 500 and 'BLOCKED' or 'OK'))
        end
    elseif cmd == 'INVENTORY' then
        local totals = {AVAILABLE=0,LOANED=0,HOLD=0,LOST=0,WITHDRAWN=0}
        local lines = {}
        for _,id in ipairs(book_order) do
            local b = books[id]
            local n = {AVAILABLE=0,LOANED=0,HOLD=0,LOST=0,WITHDRAWN=0}
            for _,c in ipairs(b.copies) do n[c.state] = n[c.state]+1 end
            for state,count in pairs(n) do totals[state] = totals[state]+count end
            lines[#lines+1] = id .. ' copies ' .. holdings(b) .. ' available ' .. n.AVAILABLE .. ' loaned ' .. n.LOANED .. ' hold ' .. n.HOLD .. ' queue ' .. #b.queue
        end
        local holding = totals.AVAILABLE+totals.LOANED+totals.HOLD
        emit('INVENTORY titles ' .. #book_order .. ' copies ' .. holding .. ' available ' .. totals.AVAILABLE .. ' loaned ' .. totals.LOANED .. ' hold ' .. totals.HOLD .. ' lost ' .. totals.LOST .. ' withdrawn ' .. totals.WITHDRAWN)
        append(out,lines)
    elseif cmd == 'STATS' then
        local active,outstanding = 0,0
        for _,m in pairs(members) do
            active,outstanding = active+size(m.loans),outstanding+balance(m)
        end
        emit('STATS day ' .. day .. ' titles ' .. #book_order .. ' members ' .. #member_order .. ' closed ' .. size(closed))
        emit('LOANS borrowed ' .. counts.borrowed .. ' returned ' .. counts.returned .. ' renewed ' .. counts.renewed .. ' lost ' .. counts.lost .. ' active ' .. active)
        emit('MONEY fines ' .. money(counts.FINE) .. ' fees ' .. money(counts.FEE) .. ' charges ' .. money(counts.PRICE) .. ' paid ' .. money(counts.paid) .. ' waived ' .. money(counts.waived) .. ' outstanding ' .. money(outstanding))
        local top = {}
        for _,b in pairs(books) do
            if b.borrowed > 0 then top[#top+1] = b end
        end
        table.sort(top,function(a,b)
            if a.borrowed ~= b.borrowed then return a.borrowed > b.borrowed end
            return a.id < b.id
        end)
        for rank = 1,math.min(3,#top) do
            local b = top[rank]
            emit('TOP ' .. rank .. ' ' .. b.id .. ' ' .. b.borrowed .. ' ' .. b.name)
        end
    end
    return out
end
local n = tonumber(io.read('*l'))
for _ = 1,n do
    local ok,out = pcall(execute,io.read('*l'))
    if ok then
        for _,line in ipairs(out) do io.write(line,'\n') end
    else
        io.write('ERROR ',out,'\n')
    end
end
