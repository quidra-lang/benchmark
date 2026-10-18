using Printf

mutable struct SharedExpense
    id::String
    day::Int
    record::Int
    payers::Vector{String}
    payments::Vector{Int}
    amount::Int
    currency::String
    category::String
    mode::String
    participants::Vector{String}
    values::Vector{Int}
    total::Int
    shares::Vector{Int}
    contributions::Vector{Int}
    interval::Int
    next_day::Int
    copies::Int
end

mutable struct ExpenseLedger
    day::Int
    serial::Int
    members::Dict{String,Tuple{Bool,Int}}
    currencies::Dict{String,Int}
    expenses::Dict{String,SharedExpense}
    used::Set{String}
    settlements::Vector{NamedTuple}
    budgets::Dict{String,Int}
end

fail(message) = throw(ArgumentError(message))
amount_text(value) = @sprintf("%d.%02d",div(value,100),value%100)
signed_text(value) = value == 0 ? "0.00" : (value > 0 ? "+" : "-")*amount_text(abs(value))
rate_text(value) = @sprintf("%d.%04d",div(value,10000),value%10000)
percentage(part,whole) = amount_text(div(part*10000,whole))*"%"
registered_names(state) = sort(collect(keys(state.members)))
active_names(state) = [name for name in registered_names(state) if state.members[name][1]]
expense_names(expense) = union(expense.payers,expense.participants)
expense_has(expense,name) = name in expense.payers || name in expense.participants
currency_note(expense) = isempty(expense.currency) ? "" : " [$(amount_text(expense.amount)) $(expense.currency)]"
chronological(state) = sort(collect(values(state.expenses));by=e -> (e.day,e.record))

function parse_amount(text)
    first,last = parse.(Int,split(text,'.'))
    return first*100+last
end

function amount_spec(text)
    parts = split(text,'@')
    return parse_amount(parts[1]),length(parts) == 1 ? "" : String(parts[2])
end

function converted(state,amount,currency)
    isempty(currency) && return amount
    haskey(state.currencies,currency) || fail("unknown currency $currency")
    return div(amount*state.currencies[currency]+5000,10000)
end

function check_member(state,name;active=true)
    haskey(state.members,name) || fail("unknown member $name")
    active && !state.members[name][1] && fail("inactive member $name")
end

function expense_ref(state,id;unfrozen=false)
    haskey(state.expenses,id) || fail("unknown expense $id")
    expense = state.expenses[id]
    if unfrozen
        for name in vcat(expense.payers,expense.participants)
            state.members[name][1] || fail("inactive member $name")
        end
    end
    return expense
end

function equal_distribution(total,k)
    quotient,remainder = divrem(total,k)
    return [quotient+(i <= remainder) for i in 1:k]
end

function largest_remainder(total,weights)
    whole = sum(weights)
    result = [div(total*weight,whole) for weight in weights]
    order = sortperm(1:length(weights);by=i -> (-mod(total*weights[i],whole),i))
    for i in 1:total-sum(result)
        result[order[i]] += 1
    end
    return result
end

function portions(expense)
    values = expense.values
    if expense.mode == "EQUAL"
        return equal_distribution(expense.amount,length(values))
    elseif expense.mode == "EXACT"
        return copy(values)
    elseif expense.mode in ("PERCENT","SHARES")
        return largest_remainder(expense.amount,values)
    end
    return equal_distribution(expense.amount-sum(values),length(values)).+values
end

function recompute!(state,expense)
    expense.total = converted(state,expense.amount,expense.currency)
    expense.shares = largest_remainder(expense.total,portions(expense))
    expense.contributions = largest_remainder(expense.total,expense.payments)
    return expense
end

function build_expense(state,id,payer,spec,category,mode,parts)
    check_member(state,payer)
    amount,currency = amount_spec(spec)
    total = converted(state,amount,currency)
    amount > 0 && total > 0 || fail("invalid amount")
    names = String[]
    values = Int[]
    if mode == "EQUAL" && parts == ["ALL"]
        names = active_names(state)
        values = zeros(Int,length(names))
    else
        for part in parts
            pieces = split(part,':')
            name = String(pieces[1])
            check_member(state,name)
            name in names && fail("duplicate member $name")
            value = 0
            if length(pieces) == 2
                value = mode in ("EXACT","ADJUST") ? parse_amount(pieces[2]) : parse(Int,pieces[2])
            end
            push!(names,name)
            push!(values,value)
        end
    end
    valid = true
    if mode == "EXACT"
        valid = sum(values) == amount
    elseif mode == "PERCENT"
        valid = sum(values) == 10000
    elseif mode == "SHARES"
        valid = sum(values) >= 1
    elseif mode == "ADJUST"
        valid = sum(values) <= amount
    end
    valid || fail("splits do not add up")
    expense = SharedExpense(id,state.day,0,[payer],[amount],amount,currency,category,mode,names,values,total,Int[],Int[],0,0,0)
    return recompute!(state,expense)
end

function balances(state)
    result = Dict(name=>0 for name in registered_names(state))
    for expense in values(state.expenses)
        for (name,value) in zip(expense.payers,expense.contributions)
            result[name] += value
        end
        for (name,value) in zip(expense.participants,expense.shares)
            result[name] -= value
        end
    end
    for settlement in state.settlements
        result[settlement.sender] += settlement.total
        result[settlement.receiver] -= settlement.total
    end
    return result
end

function expense_net(expense)
    result = Dict(name=>0 for name in expense_names(expense))
    for (name,value) in zip(expense.payers,expense.contributions)
        result[name] += value
    end
    for (name,value) in zip(expense.participants,expense.shares)
        result[name] -= value
    end
    return result
end

function greedy_transfers(names,original)
    remaining = Dict(name=>original[name] for name in names)
    output = Tuple{String,String,Int}[]
    while any(remaining[name] < 0 for name in names)
        sender = argmin(name -> remaining[name],names)
        receiver = argmax(name -> remaining[name],names)
        amount = min(-remaining[sender],remaining[receiver])
        push!(output,(sender,receiver,amount))
        remaining[sender] += amount
        remaining[receiver] -= amount
    end
    return output
end

function debts(state)
    result = Dict{Tuple{String,String},Int}()
    for expense in values(state.expenses)
        net = expense_net(expense)
        borrowers = sort([name for name in keys(net) if net[name] < 0])
        lenders = sort([name for name in keys(net) if net[name] > 0])
        i,j = 1,1
        while i <= length(borrowers) && j <= length(lenders)
            sender,receiver = borrowers[i],lenders[j]
            amount = min(-net[sender],net[receiver])
            key = (sender,receiver)
            result[key] = get(result,key,0)+amount
            net[sender] += amount
            net[receiver] -= amount
            net[sender] == 0 && (i += 1)
            net[receiver] == 0 && (j += 1)
        end
    end
    for settlement in state.settlements
        key = (settlement.sender,settlement.receiver)
        result[key] = get(result,key,0)-settlement.total
    end
    return result
end

net_debt(table,a,b) = get(table,(a,b),0)-get(table,(b,a),0)

function category_totals(state)
    result = Dict{String,Int}()
    for expense in values(state.expenses)
        result[expense.category] = get(result,expense.category,0)+expense.total
    end
    return result
end

function budget_warning(state,category)
    haskey(state.budgets,category) || return String[]
    spent = get(category_totals(state),category,0)
    over = spent-state.budgets[category]
    return over > 0 ? ["  WARNING $category over budget by $(amount_text(over))"] : String[]
end

function expense_line(command,expense;payers=false)
    names = payers ? expense.payers : expense.participants
    amounts = payers ? expense.contributions : expense.shares
    parts = ["$name $(amount_text(value))" for (name,value) in zip(names,amounts)]
    return "$command $(expense.id) $(amount_text(expense.total))$(currency_note(expense)) = "*join(parts," + ")
end

function advance_day!(state,day)
    day > state.day || fail("invalid day $day")
    output = ["DAY $day"]
    while true
        due = [expense for expense in values(state.expenses) if expense.interval > 0 && expense.next_day <= day]
        isempty(due) && break
        template = argmin(e -> (e.next_day,e.record),due)
        active = all(state.members[name][1] for name in expense_names(template))
        if !active || converted(state,template.amount,template.currency) == 0
            template.interval = 0
            template.next_day = 0
            push!(output,"  CANCEL $(template.id)")
            continue
        end
        copy_id = template.id*"#"*string(template.copies+2)
        copy = deepcopy(template)
        copy.id = copy_id
        copy.day = template.next_day
        state.serial += 1
        copy.record = state.serial
        copy.interval,copy.next_day,copy.copies = 0,0,0
        recompute!(state,copy)
        state.expenses[copy_id] = copy
        push!(state.used,copy_id)
        template.copies += 1
        template.next_day += template.interval
        push!(output,"  RECUR $copy_id $(amount_text(copy.total))")
        append!(output,budget_warning(state,copy.category))
    end
    state.day = day
    return output
end

function optimal_groups(names,bal)
    n = length(names)
    limit = 1 << n
    sums = zeros(Int,limit)
    for mask in 1:limit-1
        bit = mask & -mask
        index = trailing_zeros(bit)+1
        sums[mask+1] = sums[(mask ⊻ bit)+1]+bal[names[index]]
    end
    memo = fill(-1,limit)
    memo[1] = 0
    function best(mask)
        memo[mask+1] >= 0 && return memo[mask+1]
        first = mask & -mask
        value = 0
        subset = mask
        while subset != 0
            if subset & first != 0 && sums[subset+1] == 0
                value = max(value,1+best(mask ⊻ subset))
            end
            subset = (subset-1) & mask
        end
        memo[mask+1] = value
        return value
    end
    groups = Vector{String}[]
    mask = limit-1
    while mask != 0
        first = mask & -mask
        selected = 0
        selected_indices = Int[]
        subset = mask
        target = best(mask)
        while subset != 0
            if subset & first != 0 && sums[subset+1] == 0 && 1+best(mask ⊻ subset) == target
                indices = [i for i in 1:n if subset & (1 << (i-1)) != 0]
                if selected == 0 || isless(Tuple(indices),Tuple(selected_indices))
                    selected,selected_indices = subset,indices
                end
            end
            subset = (subset-1) & mask
        end
        push!(groups,names[selected_indices])
        mask = mask ⊻ selected
    end
    return groups
end

function ledger_summary(command,args,line,state)
    output = [command]
    names = registered_names(state)
    expenses = chronological(state)
    if command == "BALANCES"
        bal = balances(state)
        append!(output,["  $name $(signed_text(bal[name]))" for name in active_names(state)])
    elseif command == "OWES"
        name = args[1]
        check_member(state,name;active=false)
        output[1] = "OWES $name"
        table = debts(state)
        for other in names
            other == name && continue
            amount = net_debt(table,name,other)
            if amount > 0
                push!(output,"  $name owes $other $(amount_text(amount))")
            elseif amount < 0
                push!(output,"  $other owes $name $(amount_text(-amount))")
            end
        end
    elseif command == "HISTORY"
        name = args[1]
        check_member(state,name;active=false)
        output[1] = "HISTORY $name"
        records = Tuple{Int,Int,String,Int}[]
        for expense in expenses
            expense_has(expense,name) && push!(records,(expense.day,expense.record,expense.id,expense_net(expense)[name]))
        end
        for settlement in state.settlements
            if name in (settlement.sender,settlement.receiver)
                change = name == settlement.sender ? settlement.total : -settlement.total
                push!(records,(settlement.day,settlement.record,settlement.sender*"->"*settlement.receiver,change))
            end
        end
        sort!(records;by=r -> (r[1],r[2]))
        running = 0
        for (day,record,label,change) in records
            running += change
            push!(output,"  day $day $label $(signed_text(change)) balance $(signed_text(running))")
        end
    elseif command == "MATRIX"
        active = active_names(state)
        isempty(active) && return ["MATRIX","  (none)"]
        table = debts(state)
        cells = [[a == b ? "-" : amount_text(max(0,net_debt(table,a,b))) for b in active] for a in active]
        left = maximum(length,active)
        width = max(left,maximum(length(cell) for row in cells for cell in row))
        push!(output,repeat(" ",left)*join("  "*lpad(name,width) for name in active))
        for (i,name) in enumerate(active)
            push!(output,rpad(name,left)*join("  "*lpad(cell,width) for cell in cells[i]))
        end
    elseif command == "CATEGORY"
        totals = category_totals(state)
        whole = sum(values(totals);init=0)
        for category in sort(collect(keys(totals));by=c -> (-totals[c],c))
            total = totals[category]
            push!(output,"  $category $(amount_text(total)) $(percentage(total,whole))")
            shares = Dict(name=>0 for name in names)
            for expense in expenses
                if expense.category == category
                    for (name,value) in zip(expense.participants,expense.shares)
                        shares[name] += value
                    end
                end
            end
            for name in sort([name for name in names if shares[name] > 0];by=name -> (-shares[name],name))
                push!(output,"    $name $(amount_text(shares[name])) $(percentage(shares[name],total))")
            end
        end
    elseif command == "BUDGETS"
        totals = category_totals(state)
        for category in sort(collect(keys(state.budgets)))
            spent,budget = get(totals,category,0),state.budgets[category]
            label = spent <= budget ? "left" : "over"
            push!(output,"  $category spent $(amount_text(spent)) budget $(amount_text(budget)) used $(percentage(spent,budget)) $label $(amount_text(abs(budget-spent)))")
        end
    elseif command == "TOTALS"
        for name in names
            paid,share,sent,received = 0,0,0,0
            for expense in expenses
                paid += sum((value for (payer,value) in zip(expense.payers,expense.contributions) if payer == name);init=0)
                share += sum((value for (person,value) in zip(expense.participants,expense.shares) if person == name);init=0)
            end
            for settlement in state.settlements
                settlement.sender == name && (sent += settlement.total)
                settlement.receiver == name && (received += settlement.total)
            end
            push!(output,"  $name paid $(amount_text(paid)) share $(amount_text(share)) sent $(amount_text(sent)) received $(amount_text(received))")
        end
        currencies = sort(unique([e.currency for e in expenses if !isempty(e.currency)]))
        for currency in currencies
            selected = filter(e -> e.currency == currency,expenses)
            push!(output,"  currency $currency expenses $(length(selected)) amount $(amount_text(sum(e.amount for e in selected))) base $(amount_text(sum(e.total for e in selected)))")
        end
        total = sum((e.total for e in expenses);init=0)
        settled = sum((s.total for s in state.settlements);init=0)
        push!(output,"  expenses $(length(expenses)) total $(amount_text(total)) settlements $(length(state.settlements)) total $(amount_text(settled))")
    elseif command == "MEMBERS"
        for name in names
            active,day = state.members[name]
            status = active ? "active" : "left"
            count = sum((expense_has(e,name) for e in expenses);init=0)
            push!(output,"  $name $status day $day expenses $count")
        end
    elseif command == "EXPENSES"
        output[1] = line
        mode = args[1]
        mode == "MEMBER" && check_member(state,args[2];active=false)
        selected = filter(expenses) do expense
            mode == "ALL" || (mode == "CATEGORY" && expense.category == args[2]) ||
                (mode == "MEMBER" && expense_has(expense,args[2])) ||
                (mode == "DAYS" && parse(Int,args[2]) <= expense.day <= parse(Int,args[3]))
        end
        for expense in selected
            push!(output,"  day $(expense.day) $(expense.id) $(expense.category) $(amount_text(expense.total)) by $(join(expense.payers,","))")
        end
        push!(output,"  count $(length(selected)) total $(amount_text(sum((e.total for e in selected);init=0)))")
    elseif command == "PERIODS"
        k = parse(Int,args[1])
        output[1] = "PERIODS $k"
        groups = Dict{Int,Vector{SharedExpense}}()
        for expense in expenses
            i = div(expense.day-1,k)
            push!(get!(groups,i,SharedExpense[]),expense)
        end
        for i in sort(collect(keys(groups)))
            group = groups[i]
            push!(output,"  days $(i*k+1)-$(i*k+k) expenses $(length(group)) total $(amount_text(sum(e.total for e in group)))")
        end
    elseif command == "SHOW"
        expense = expense_ref(state,args[1])
        output[1] = "SHOW $(expense.id)"
        push!(output,"  day $(expense.day) category $(expense.category) mode $(expense.mode) total $(amount_text(expense.total))$(currency_note(expense))")
        for (name,value) in zip(expense.payers,expense.contributions)
            push!(output,"  paid $name $(amount_text(value))")
        end
        for (name,share,value) in zip(expense.participants,expense.shares,expense.values)
            suffix = ""
            if expense.mode == "EXACT"
                suffix = " "*amount_text(value)
            elseif expense.mode == "PERCENT"
                suffix = " "*amount_text(value)*"%"
            elseif expense.mode == "SHARES"
                suffix = " $value/$(sum(expense.values))"
            elseif expense.mode == "ADJUST"
                suffix = " +"*amount_text(value)
            end
            push!(output,"  share $name $(amount_text(share))$suffix")
        end
        expense.interval > 0 && push!(output,"  recurring interval $(expense.interval) next $(expense.next_day)")
    elseif command == "SIMPLIFY"
        bal = balances(state)
        selected = [name for name in names if bal[name] != 0]
        if args[1] == "GREEDY"
            transfers = greedy_transfers(selected,bal)
            output[1] = "SIMPLIFY GREEDY transfers $(length(transfers))"
            append!(output,["  $sender -> $receiver $(amount_text(value))" for (sender,receiver,value) in transfers])
        else
            length(selected) <= 12 || fail("too many members")
            groups = optimal_groups(selected,bal)
            transfers = [greedy_transfers(group,bal) for group in groups]
            count = sum(length,transfers;init=0)
            output[1] = "SIMPLIFY OPTIMAL transfers $count groups $(length(groups))"
            for (group,items) in zip(groups,transfers)
                push!(output,"  group "*join(group," "))
                append!(output,["    $sender -> $receiver $(amount_text(value))" for (sender,receiver,value) in items])
            end
        end
    end
    if command in ("BALANCES","OWES","HISTORY","CATEGORY","BUDGETS","MEMBERS","PERIODS") && length(output) == 1
        push!(output,"  (none)")
    end
    return output
end

function execute(line,state)
    tokens = String.(split(line,' '))
    command,args = tokens[1],tokens[2:end]
    if command == "DAY"
        return advance_day!(state,parse(Int,args[1]))
    elseif command == "MEMBER"
        name = args[1]
        haskey(state.members,name) && state.members[name][1] && fail("duplicate member $name")
        label = haskey(state.members,name) ? "rejoined" : "joined"
        state.members[name] = (true,state.day)
        return ["MEMBER $name $label"]
    elseif command == "LEAVE"
        name = args[1]
        check_member(state,name)
        balances(state)[name] == 0 || fail("member has a balance $name")
        state.members[name] = (false,state.day)
        return ["LEAVE $name"]
    elseif command == "CURRENCY"
        currency,rate = args[1],parse(Int,args[2])
        suffix = haskey(state.currencies,currency) ? " was "*rate_text(state.currencies[currency]) : ""
        state.currencies[currency] = rate
        return ["CURRENCY $currency $(rate_text(rate))$suffix"]
    elseif command in ("EXPENSE","EDIT")
        id,payer,spec,category,mode = args[1:5]
        if command == "EXPENSE"
            id in state.used && fail("duplicate id $id")
        else
            original = expense_ref(state,id;unfrozen=true)
        end
        expense = build_expense(state,id,payer,spec,category,mode,args[6:end])
        if command == "EDIT"
            expense.day,expense.record = original.day,original.record
            expense.interval,expense.next_day,expense.copies = original.interval,original.next_day,original.copies
        else
            state.serial += 1
            expense.record = state.serial
            push!(state.used,id)
        end
        state.expenses[id] = expense
        return vcat([expense_line(command,expense)],budget_warning(state,category))
    elseif command == "PAYERS"
        expense = expense_ref(state,args[1];unfrozen=true)
        names = String[]
        payments = Int[]
        for part in args[2:end]
            name,amount = split(part,':')
            check_member(state,name)
            name in names && fail("duplicate member $name")
            push!(names,name)
            push!(payments,parse_amount(amount))
        end
        sum(payments) == expense.amount || fail("payers do not add up")
        contributions = largest_remainder(expense.total,payments)
        expense.payers,expense.payments,expense.contributions = names,payments,contributions
        return [expense_line(command,expense;payers=true)]
    elseif command == "DELETE"
        expense_ref(state,args[1];unfrozen=true)
        delete!(state.expenses,args[1])
        return ["DELETE $(args[1])"]
    elseif command == "RECURRING"
        expense = expense_ref(state,args[1])
        interval = parse(Int,args[2])
        expense.interval = interval
        expense.next_day = interval == 0 ? 0 : state.day+interval
        return interval == 0 ? ["RECURRING $(expense.id) stopped"] : ["RECURRING $(expense.id) interval $interval next $(expense.next_day)"]
    elseif command == "SETTLE"
        sender,receiver,spec = args
        check_member(state,sender)
        check_member(state,receiver)
        sender != receiver || fail("same member $sender")
        amount,currency = amount_spec(spec)
        total = converted(state,amount,currency)
        amount > 0 && total > 0 || fail("invalid amount")
        state.serial += 1
        settlement = (day=state.day,record=state.serial,sender=sender,receiver=receiver,amount=amount,currency=currency,total=total)
        push!(state.settlements,settlement)
        return ["SETTLE $sender -> $receiver $(amount_text(total))$(currency_note(settlement))"]
    elseif command == "BUDGET"
        category,amount = args[1],parse_amount(args[2])
        if amount == 0
            delete!(state.budgets,category)
            return ["BUDGET $category removed"]
        end
        state.budgets[category] = amount
        return ["BUDGET $category $(amount_text(amount))"]
    end
    return ledger_summary(command,args,line,state)
end

function main()
    state = ExpenseLedger(1,0,Dict{String,Tuple{Bool,Int}}(),Dict{String,Int}(),Dict{String,SharedExpense}(),Set{String}(),NamedTuple[],Dict{String,Int}())
    count = parse(Int,readline())
    for i in 1:count
        line = readline()
        try
            foreach(println,execute(line,state))
        catch exception
            exception isa ArgumentError || rethrow()
            println("ERROR ",exception.msg)
        end
    end
end
main()
