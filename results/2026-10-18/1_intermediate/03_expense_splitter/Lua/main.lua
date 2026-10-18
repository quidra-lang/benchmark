local function words(text)
    local result = {}
    for word in text:gmatch("[^ ]+") do
        result[#result + 1] = word
    end
    return result
end

local function sorted_keys(map)
    local result = {}
    for key in pairs(map) do
        result[#result + 1] = key
    end
    table.sort(result)
    return result
end

local function contains(values, value)
    for _, other in ipairs(values) do
        if other == value then
            return true
        end
    end
    return false
end

local function total(values)
    local result = 0
    for _, value in ipairs(values) do
        result = result + value
    end
    return result
end

local function append(output, values)
    for _, value in ipairs(values) do
        output[#output + 1] = value
    end
end

local function fail(message)
    error(message, 0)
end

local function amount_text(value)
    return string.format("%d.%02d", value // 100, value % 100)
end

local function signed_text(value)
    if value == 0 then
        return "0.00"
    end
    return (value > 0 and "+" or "-") .. amount_text(math.abs(value))
end

local function rate_text(value)
    return string.format("%d.%04d", value // 10000, value % 10000)
end

local function percentage(part, whole)
    return amount_text((part * 10000) // whole) .. "%"
end

local function active_names(state)
    local result = {}
    for _, name in ipairs(sorted_keys(state.members)) do
        if state.members[name].active then
            result[#result + 1] = name
        end
    end
    return result
end

local function expense_names(expense)
    local result = {}
    for _, names in ipairs({expense.payers, expense.participants}) do
        for _, name in ipairs(names) do
            if not contains(result, name) then
                result[#result + 1] = name
            end
        end
    end
    return result
end

local function expense_has(expense, name)
    return contains(expense.payers, name) or contains(expense.participants, name)
end

local function currency_note(record)
    if record.currency == "" then
        return ""
    end
    return " [" .. amount_text(record.amount) .. " " .. record.currency .. "]"
end

local function chronological(state)
    local result = {}
    for _, expense in pairs(state.expenses) do
        result[#result + 1] = expense
    end
    table.sort(result, function(a, b)
        if a.day ~= b.day then
            return a.day < b.day
        end
        return a.record < b.record
    end)
    return result
end

local function parse_amount(text)
    local whole, fraction = text:match("^(%d+)%.(%d%d)$")
    return tonumber(whole) * 100 + tonumber(fraction)
end

local function amount_spec(text)
    local amount, currency = text:match("^(.-)@([A-Z]+)$")
    if currency then
        return parse_amount(amount), currency
    end
    return parse_amount(text), ""
end

local function converted(state, amount, currency)
    if currency == "" then
        return amount
    end
    if not state.currencies[currency] then
        fail("unknown currency " .. currency)
    end
    return (amount * state.currencies[currency] + 5000) // 10000
end

local function check_member(state, name, active)
    if not state.members[name] then
        fail("unknown member " .. name)
    end
    if active ~= false and not state.members[name].active then
        fail("inactive member " .. name)
    end
end

local function expense_ref(state, id, unfrozen)
    local expense = state.expenses[id]
    if not expense then
        fail("unknown expense " .. id)
    end
    if unfrozen then
        for _, names in ipairs({expense.payers, expense.participants}) do
            for _, name in ipairs(names) do
                if not state.members[name].active then
                    fail("inactive member " .. name)
                end
            end
        end
    end
    return expense
end

local function equal_distribution(value, k)
    local result = {}
    for i = 1, k do
        result[i] = value // k + (i <= value % k and 1 or 0)
    end
    return result
end

local function largest_remainder(value, weights)
    local whole = total(weights)
    local result, order = {}, {}
    for i, weight in ipairs(weights) do
        result[i] = (value * weight) // whole
        order[i] = i
    end
    table.sort(order, function(a, b)
        local ra, rb = (value * weights[a]) % whole, (value * weights[b]) % whole
        if ra ~= rb then
            return ra > rb
        end
        return a < b
    end)
    for i = 1, value - total(result) do
        result[order[i]] = result[order[i]] + 1
    end
    return result
end

local function portions(expense)
    if expense.mode == "EQUAL" then
        return equal_distribution(expense.amount, #expense.values)
    elseif expense.mode == "EXACT" then
        return expense.values
    elseif expense.mode == "PERCENT" or expense.mode == "SHARES" then
        return largest_remainder(expense.amount, expense.values)
    end
    local result = equal_distribution(expense.amount - total(expense.values), #expense.values)
    for i, extra in ipairs(expense.values) do
        result[i] = result[i] + extra
    end
    return result
end

local function recompute(state, expense)
    expense.total = converted(state, expense.amount, expense.currency)
    expense.shares = largest_remainder(expense.total, portions(expense))
    expense.contributions = largest_remainder(expense.total, expense.payments)
    return expense
end

local function build_expense(state, id, payer, spec, category, mode, parts)
    check_member(state, payer)
    local amount, currency = amount_spec(spec)
    local converted_total = converted(state, amount, currency)
    if amount == 0 or converted_total == 0 then
        fail("invalid amount")
    end
    local names, values = {}, {}
    if mode == "EQUAL" and #parts == 1 and parts[1] == "ALL" then
        names = active_names(state)
        for i = 1, #names do
            values[i] = 0
        end
    else
        for _, part in ipairs(parts) do
            local name, text = part:match("^([^:]+):(.+)$")
            name = name or part
            check_member(state, name)
            if contains(names, name) then
                fail("duplicate member " .. name)
            end
            local value = 0
            if text then
                if mode == "EXACT" or mode == "ADJUST" then
                    value = parse_amount(text)
                else
                    value = tonumber(text)
                end
            end
            names[#names + 1] = name
            values[#values + 1] = value
        end
    end
    local sum = total(values)
    local valid = true
    if mode == "EXACT" then
        valid = sum == amount
    elseif mode == "PERCENT" then
        valid = sum == 10000
    elseif mode == "SHARES" then
        valid = sum >= 1
    elseif mode == "ADJUST" then
        valid = sum <= amount
    end
    if not valid then
        fail("splits do not add up")
    end
    return recompute(state, {id = id, day = state.day, record = 0, payers = {payer}, payments = {amount},
        amount = amount, currency = currency, category = category, mode = mode, participants = names,
        values = values, total = converted_total, shares = {}, contributions = {}, interval = 0, next_day = 0, copies = 0})
end

local function expense_net(expense)
    local result = {}
    for _, name in ipairs(expense_names(expense)) do
        result[name] = 0
    end
    for i, name in ipairs(expense.payers) do
        result[name] = result[name] + expense.contributions[i]
    end
    for i, name in ipairs(expense.participants) do
        result[name] = result[name] - expense.shares[i]
    end
    return result
end

local function balances(state)
    local result = {}
    for name in pairs(state.members) do
        result[name] = 0
    end
    for _, expense in pairs(state.expenses) do
        for name, net in pairs(expense_net(expense)) do
            result[name] = result[name] + net
        end
    end
    for _, settlement in ipairs(state.settlements) do
        result[settlement.sender] = result[settlement.sender] + settlement.total
        result[settlement.receiver] = result[settlement.receiver] - settlement.total
    end
    return result
end

local function greedy_transfers(names, original)
    local remaining = {}
    for _, name in ipairs(names) do
        remaining[name] = original[name]
    end
    local output = {}
    while #names > 0 do
        local sender, receiver = names[1], names[1]
        for _, name in ipairs(names) do
            if remaining[name] < remaining[sender] then
                sender = name
            end
            if remaining[name] > remaining[receiver] then
                receiver = name
            end
        end
        if remaining[sender] >= 0 then
            break
        end
        local amount = math.min(-remaining[sender], remaining[receiver])
        output[#output + 1] = {sender, receiver, amount}
        remaining[sender] = remaining[sender] + amount
        remaining[receiver] = remaining[receiver] - amount
    end
    return output
end

local function debts(state)
    local result = {}
    local function add(a, b, value)
        result[a] = result[a] or {}
        result[a][b] = (result[a][b] or 0) + value
    end
    for _, expense in pairs(state.expenses) do
        local net = expense_net(expense)
        local borrowers, lenders = {}, {}
        for _, name in ipairs(sorted_keys(net)) do
            if net[name] < 0 then
                borrowers[#borrowers + 1] = name
            elseif net[name] > 0 then
                lenders[#lenders + 1] = name
            end
        end
        local i, j = 1, 1
        while i <= #borrowers and j <= #lenders do
            local sender, receiver = borrowers[i], lenders[j]
            local amount = math.min(-net[sender], net[receiver])
            add(sender, receiver, amount)
            net[sender] = net[sender] + amount
            net[receiver] = net[receiver] - amount
            if net[sender] == 0 then
                i = i + 1
            end
            if net[receiver] == 0 then
                j = j + 1
            end
        end
    end
    for _, s in ipairs(state.settlements) do
        add(s.sender, s.receiver, -s.total)
    end
    return result
end

local function net_debt(map, a, b)
    return (map[a] and map[a][b] or 0) - (map[b] and map[b][a] or 0)
end

local function category_totals(state)
    local result = {}
    for _, expense in pairs(state.expenses) do
        result[expense.category] = (result[expense.category] or 0) + expense.total
    end
    return result
end

local function budget_warning(state, category)
    if not state.budgets[category] then
        return {}
    end
    local spent = category_totals(state)[category] or 0
    local over = spent - state.budgets[category]
    return over > 0 and {"  WARNING " .. category .. " over budget by " .. amount_text(over)} or {}
end

local function expense_line(command, expense, payers)
    local names = payers and expense.payers or expense.participants
    local amounts = payers and expense.contributions or expense.shares
    local parts = {}
    for i, name in ipairs(names) do
        parts[i] = name .. " " .. amount_text(amounts[i])
    end
    return command .. " " .. expense.id .. " " .. amount_text(expense.total) .. currency_note(expense) .. " = " .. table.concat(parts, " + ")
end

local function copy_expense(expense)
    local result = {}
    for key, value in pairs(expense) do
        if type(value) == "table" then
            local list = {}
            for i, item in ipairs(value) do
                list[i] = item
            end
            result[key] = list
        else
            result[key] = value
        end
    end
    return result
end

local function advance_day(state, day)
    if day <= state.day then
        fail("invalid day " .. day)
    end
    local output = {"DAY " .. day}
    while true do
        local template
        for _, expense in pairs(state.expenses) do
            if expense.interval > 0 and expense.next_day <= day then
                if not template or expense.next_day < template.next_day or (expense.next_day == template.next_day and expense.record < template.record) then
                    template = expense
                end
            end
        end
        if not template then
            break
        end
        local active = true
        for _, name in ipairs(expense_names(template)) do
            if not state.members[name].active then
                active = false
            end
        end
        if not active or converted(state, template.amount, template.currency) == 0 then
            template.interval, template.next_day = 0, 0
            output[#output + 1] = "  CANCEL " .. template.id
        else
            local copy_id = template.id .. "#" .. (template.copies + 2)
            local copy = copy_expense(template)
            copy.id, copy.day = copy_id, template.next_day
            state.serial = state.serial + 1
            copy.record = state.serial
            copy.interval, copy.next_day, copy.copies = 0, 0, 0
            recompute(state, copy)
            state.expenses[copy_id] = copy
            state.used[copy_id] = true
            template.copies = template.copies + 1
            template.next_day = template.next_day + template.interval
            output[#output + 1] = "  RECUR " .. copy_id .. " " .. amount_text(copy.total)
            append(output, budget_warning(state, copy.category))
        end
    end
    state.day = day
    return output
end

local function vector_less(a, b)
    for i = 1, math.min(#a, #b) do
        if a[i] ~= b[i] then
            return a[i] < b[i]
        end
    end
    return #a < #b
end

local function optimal_groups(names, bal)
    local n = #names
    local limit = 1 << n
    local sums, bit_index = {[0] = 0}, {}
    for i = 1, n do
        bit_index[1 << (i - 1)] = i
    end
    for mask = 1, limit - 1 do
        local bit = mask & -mask
        sums[mask] = sums[mask ~ bit] + bal[names[bit_index[bit]]]
    end
    local memo = {[0] = 0}
    local function best(mask)
        if memo[mask] then
            return memo[mask]
        end
        local first, value, subset = mask & -mask, 0, mask
        while subset ~= 0 do
            if (subset & first) ~= 0 and sums[subset] == 0 then
                value = math.max(value, 1 + best(mask ~ subset))
            end
            subset = (subset - 1) & mask
        end
        memo[mask] = value
        return value
    end
    local groups, mask = {}, limit - 1
    while mask ~= 0 do
        local first, selected, selected_indices = mask & -mask, 0, {}
        local target, subset = best(mask), mask
        while subset ~= 0 do
            if (subset & first) ~= 0 and sums[subset] == 0 and 1 + best(mask ~ subset) == target then
                local indices = {}
                for i = 1, n do
                    if (subset & (1 << (i - 1))) ~= 0 then
                        indices[#indices + 1] = i
                    end
                end
                if selected == 0 or vector_less(indices, selected_indices) then
                    selected, selected_indices = subset, indices
                end
            end
            subset = (subset - 1) & mask
        end
        local group = {}
        for i, index in ipairs(selected_indices) do
            group[i] = names[index]
        end
        groups[#groups + 1] = group
        mask = mask ~ selected
    end
    return groups
end

local function ledger_summary(command, args, line, state)
    local output = {command}
    local names, expenses = sorted_keys(state.members), chronological(state)
    if command == "BALANCES" then
        local bal = balances(state)
        for _, name in ipairs(active_names(state)) do
            output[#output + 1] = "  " .. name .. " " .. signed_text(bal[name])
        end
    elseif command == "OWES" then
        local name = args[1]
        check_member(state, name, false)
        output[1] = "OWES " .. name
        local map = debts(state)
        for _, other in ipairs(names) do
            if name ~= other then
                local amount = net_debt(map, name, other)
                if amount > 0 then
                    output[#output + 1] = "  " .. name .. " owes " .. other .. " " .. amount_text(amount)
                elseif amount < 0 then
                    output[#output + 1] = "  " .. other .. " owes " .. name .. " " .. amount_text(-amount)
                end
            end
        end
    elseif command == "HISTORY" then
        local name = args[1]
        check_member(state, name, false)
        output[1] = "HISTORY " .. name
        local records = {}
        for _, e in ipairs(expenses) do
            if expense_has(e, name) then
                records[#records + 1] = {e.day, e.record, e.id, expense_net(e)[name]}
            end
        end
        for _, s in ipairs(state.settlements) do
            if name == s.sender or name == s.receiver then
                records[#records + 1] = {s.day, s.record, s.sender .. "->" .. s.receiver, name == s.sender and s.total or -s.total}
            end
        end
        table.sort(records, function(a, b)
            if a[1] ~= b[1] then
                return a[1] < b[1]
            end
            return a[2] < b[2]
        end)
        local running = 0
        for _, record in ipairs(records) do
            local day, serial, label, change = table.unpack(record)
            running = running + change
            output[#output + 1] = "  day " .. day .. " " .. label .. " " .. signed_text(change) .. " balance " .. signed_text(running)
        end
    elseif command == "MATRIX" then
        local active = active_names(state)
        if #active == 0 then
            return {"MATRIX", "  (none)"}
        end
        local map, cells, left, width = debts(state), {}, 0, 0
        for _, name in ipairs(active) do
            left = math.max(left, #name)
            width = math.max(width, #name)
        end
        for i, a in ipairs(active) do
            cells[i] = {}
            for j, b in ipairs(active) do
                local cell = a == b and "-" or amount_text(math.max(0, net_debt(map, a, b)))
                cells[i][j] = cell
                width = math.max(width, #cell)
            end
        end
        local header = string.rep(" ", left)
        for _, name in ipairs(active) do
            header = header .. "  " .. string.rep(" ", width - #name) .. name
        end
        output[#output + 1] = header
        for i, name in ipairs(active) do
            local row = name .. string.rep(" ", left - #name)
            for _, cell in ipairs(cells[i]) do
                row = row .. "  " .. string.rep(" ", width - #cell) .. cell
            end
            output[#output + 1] = row
        end
    elseif command == "CATEGORY" then
        local totals, whole = category_totals(state), 0
        for _, value in pairs(totals) do
            whole = whole + value
        end
        local categories = sorted_keys(totals)
        table.sort(categories, function(a, b)
            if totals[a] ~= totals[b] then
                return totals[a] > totals[b]
            end
            return a < b
        end)
        for _, category in ipairs(categories) do
            local value = totals[category]
            output[#output + 1] = "  " .. category .. " " .. amount_text(value) .. " " .. percentage(value, whole)
            local shares = {}
            for _, name in ipairs(names) do
                shares[name] = 0
            end
            for _, e in ipairs(expenses) do
                if e.category == category then
                    for i, name in ipairs(e.participants) do
                        shares[name] = shares[name] + e.shares[i]
                    end
                end
            end
            local people = {}
            for _, name in ipairs(names) do
                if shares[name] > 0 then
                    people[#people + 1] = name
                end
            end
            table.sort(people, function(a, b)
                if shares[a] ~= shares[b] then
                    return shares[a] > shares[b]
                end
                return a < b
            end)
            for _, name in ipairs(people) do
                output[#output + 1] = "    " .. name .. " " .. amount_text(shares[name]) .. " " .. percentage(shares[name], value)
            end
        end
    elseif command == "BUDGETS" then
        local totals = category_totals(state)
        for _, category in ipairs(sorted_keys(state.budgets)) do
            local spent, budget = totals[category] or 0, state.budgets[category]
            local label = spent <= budget and "left" or "over"
            output[#output + 1] = "  " .. category .. " spent " .. amount_text(spent) .. " budget " .. amount_text(budget) .. " used " .. percentage(spent, budget) .. " " .. label .. " " .. amount_text(math.abs(budget - spent))
        end
    elseif command == "TOTALS" then
        for _, name in ipairs(names) do
            local paid, share, sent, received = 0, 0, 0, 0
            for _, e in ipairs(expenses) do
                for i, payer in ipairs(e.payers) do
                    if payer == name then
                        paid = paid + e.contributions[i]
                    end
                end
                for i, person in ipairs(e.participants) do
                    if person == name then
                        share = share + e.shares[i]
                    end
                end
            end
            for _, s in ipairs(state.settlements) do
                if s.sender == name then
                    sent = sent + s.total
                end
                if s.receiver == name then
                    received = received + s.total
                end
            end
            output[#output + 1] = "  " .. name .. " paid " .. amount_text(paid) .. " share " .. amount_text(share) .. " sent " .. amount_text(sent) .. " received " .. amount_text(received)
        end
        local currencies, expense_total, settlement_total = {}, 0, 0
        for _, e in ipairs(expenses) do
            expense_total = expense_total + e.total
            if e.currency ~= "" then
                local value = currencies[e.currency] or {count = 0, amount = 0, total = 0}
                value.count = value.count + 1
                value.amount = value.amount + e.amount
                value.total = value.total + e.total
                currencies[e.currency] = value
            end
        end
        for _, currency in ipairs(sorted_keys(currencies)) do
            local value = currencies[currency]
            output[#output + 1] = "  currency " .. currency .. " expenses " .. value.count .. " amount " .. amount_text(value.amount) .. " base " .. amount_text(value.total)
        end
        for _, s in ipairs(state.settlements) do
            settlement_total = settlement_total + s.total
        end
        output[#output + 1] = "  expenses " .. #expenses .. " total " .. amount_text(expense_total) .. " settlements " .. #state.settlements .. " total " .. amount_text(settlement_total)
    elseif command == "MEMBERS" then
        for _, name in ipairs(names) do
            local member, count = state.members[name], 0
            for _, e in ipairs(expenses) do
                if expense_has(e, name) then
                    count = count + 1
                end
            end
            output[#output + 1] = "  " .. name .. " " .. (member.active and "active" or "left") .. " day " .. member.day .. " expenses " .. count
        end
    elseif command == "EXPENSES" then
        output[1] = line
        local mode, count, sum = args[1], 0, 0
        if mode == "MEMBER" then
            check_member(state, args[2], false)
        end
        for _, e in ipairs(expenses) do
            local matches = mode == "ALL" or (mode == "CATEGORY" and e.category == args[2]) or
                (mode == "MEMBER" and expense_has(e, args[2])) or
                (mode == "DAYS" and e.day >= tonumber(args[2]) and e.day <= tonumber(args[3]))
            if matches then
                count, sum = count + 1, sum + e.total
                output[#output + 1] = "  day " .. e.day .. " " .. e.id .. " " .. e.category .. " " .. amount_text(e.total) .. " by " .. table.concat(e.payers, ",")
            end
        end
        output[#output + 1] = "  count " .. count .. " total " .. amount_text(sum)
    elseif command == "PERIODS" then
        local k = tonumber(args[1])
        output[1] = "PERIODS " .. k
        local groups = {}
        for _, e in ipairs(expenses) do
            local i = (e.day - 1) // k
            groups[i] = groups[i] or {count = 0, total = 0}
            groups[i].count = groups[i].count + 1
            groups[i].total = groups[i].total + e.total
        end
        for _, i in ipairs(sorted_keys(groups)) do
            local group = groups[i]
            output[#output + 1] = "  days " .. (i * k + 1) .. "-" .. (i * k + k) .. " expenses " .. group.count .. " total " .. amount_text(group.total)
        end
    elseif command == "SHOW" then
        local e = expense_ref(state, args[1])
        output[1] = "SHOW " .. e.id
        output[#output + 1] = "  day " .. e.day .. " category " .. e.category .. " mode " .. e.mode .. " total " .. amount_text(e.total) .. currency_note(e)
        for i, name in ipairs(e.payers) do
            output[#output + 1] = "  paid " .. name .. " " .. amount_text(e.contributions[i])
        end
        for i, name in ipairs(e.participants) do
            local value, suffix = e.values[i], ""
            if e.mode == "EXACT" then
                suffix = " " .. amount_text(value)
            elseif e.mode == "PERCENT" then
                suffix = " " .. amount_text(value) .. "%"
            elseif e.mode == "SHARES" then
                suffix = " " .. value .. "/" .. total(e.values)
            elseif e.mode == "ADJUST" then
                suffix = " +" .. amount_text(value)
            end
            output[#output + 1] = "  share " .. name .. " " .. amount_text(e.shares[i]) .. suffix
        end
        if e.interval > 0 then
            output[#output + 1] = "  recurring interval " .. e.interval .. " next " .. e.next_day
        end
    elseif command == "SIMPLIFY" then
        local bal, selected = balances(state), {}
        for _, name in ipairs(names) do
            if bal[name] ~= 0 then
                selected[#selected + 1] = name
            end
        end
        if args[1] == "GREEDY" then
            local transfers = greedy_transfers(selected, bal)
            output[1] = "SIMPLIFY GREEDY transfers " .. #transfers
            for _, transfer in ipairs(transfers) do
                output[#output + 1] = "  " .. transfer[1] .. " -> " .. transfer[2] .. " " .. amount_text(transfer[3])
            end
        else
            if #selected > 12 then
                fail("too many members")
            end
            local groups = optimal_groups(selected, bal)
            local transfers, count = {}, 0
            for i, group in ipairs(groups) do
                transfers[i] = greedy_transfers(group, bal)
                count = count + #transfers[i]
            end
            output[1] = "SIMPLIFY OPTIMAL transfers " .. count .. " groups " .. #groups
            for i, group in ipairs(groups) do
                output[#output + 1] = "  group " .. table.concat(group, " ")
                for _, transfer in ipairs(transfers[i]) do
                    output[#output + 1] = "    " .. transfer[1] .. " -> " .. transfer[2] .. " " .. amount_text(transfer[3])
                end
            end
        end
    end
    if contains({"BALANCES", "OWES", "HISTORY", "CATEGORY", "BUDGETS", "MEMBERS", "PERIODS"}, command) and #output == 1 then
        output[2] = "  (none)"
    end
    return output
end

local function execute(line, state)
    local tokens = words(line)
    local command = table.remove(tokens, 1)
    local args = tokens
    if command == "DAY" then
        return advance_day(state, tonumber(args[1]))
    elseif command == "MEMBER" then
        local name = args[1]
        if state.members[name] and state.members[name].active then
            fail("duplicate member " .. name)
        end
        local label = state.members[name] and "rejoined" or "joined"
        state.members[name] = {active = true, day = state.day}
        return {"MEMBER " .. name .. " " .. label}
    elseif command == "LEAVE" then
        local name = args[1]
        check_member(state, name)
        if balances(state)[name] ~= 0 then
            fail("member has a balance " .. name)
        end
        state.members[name] = {active = false, day = state.day}
        return {"LEAVE " .. name}
    elseif command == "CURRENCY" then
        local currency, rate = args[1], tonumber(args[2])
        local suffix = state.currencies[currency] and " was " .. rate_text(state.currencies[currency]) or ""
        state.currencies[currency] = rate
        return {"CURRENCY " .. currency .. " " .. rate_text(rate) .. suffix}
    elseif command == "EXPENSE" or command == "EDIT" then
        local id, payer, spec, category, mode = table.unpack(args, 1, 5)
        local original
        if command == "EXPENSE" then
            if state.used[id] then
                fail("duplicate id " .. id)
            end
        else
            original = expense_ref(state, id, true)
        end
        local parts = {}
        for i = 6, #args do
            parts[#parts + 1] = args[i]
        end
        local expense = build_expense(state, id, payer, spec, category, mode, parts)
        if original then
            expense.day, expense.record = original.day, original.record
            expense.interval, expense.next_day, expense.copies = original.interval, original.next_day, original.copies
        else
            state.serial = state.serial + 1
            expense.record = state.serial
            state.used[id] = true
        end
        state.expenses[id] = expense
        local output = {expense_line(command, expense)}
        append(output, budget_warning(state, category))
        return output
    elseif command == "PAYERS" then
        local expense = expense_ref(state, args[1], true)
        local names, payments = {}, {}
        for i = 2, #args do
            local name, amount = args[i]:match("^([^:]+):(.+)$")
            check_member(state, name)
            if contains(names, name) then
                fail("duplicate member " .. name)
            end
            names[#names + 1] = name
            payments[#payments + 1] = parse_amount(amount)
        end
        if total(payments) ~= expense.amount then
            fail("payers do not add up")
        end
        local contributions = largest_remainder(expense.total, payments)
        expense.payers, expense.payments, expense.contributions = names, payments, contributions
        return {expense_line(command, expense, true)}
    elseif command == "DELETE" then
        expense_ref(state, args[1], true)
        state.expenses[args[1]] = nil
        return {"DELETE " .. args[1]}
    elseif command == "RECURRING" then
        local expense = expense_ref(state, args[1])
        local interval = tonumber(args[2])
        expense.interval = interval
        expense.next_day = interval == 0 and 0 or state.day + interval
        if interval == 0 then
            return {"RECURRING " .. expense.id .. " stopped"}
        end
        return {"RECURRING " .. expense.id .. " interval " .. interval .. " next " .. expense.next_day}
    elseif command == "SETTLE" then
        local sender, receiver, spec = table.unpack(args)
        check_member(state, sender)
        check_member(state, receiver)
        if sender == receiver then
            fail("same member " .. sender)
        end
        local amount, currency = amount_spec(spec)
        local value = converted(state, amount, currency)
        if amount == 0 or value == 0 then
            fail("invalid amount")
        end
        state.serial = state.serial + 1
        local settlement = {day = state.day, record = state.serial, sender = sender, receiver = receiver,
            amount = amount, currency = currency, total = value}
        state.settlements[#state.settlements + 1] = settlement
        return {"SETTLE " .. sender .. " -> " .. receiver .. " " .. amount_text(value) .. currency_note(settlement)}
    elseif command == "BUDGET" then
        local category, amount = args[1], parse_amount(args[2])
        if amount == 0 then
            state.budgets[category] = nil
            return {"BUDGET " .. category .. " removed"}
        end
        state.budgets[category] = amount
        return {"BUDGET " .. category .. " " .. amount_text(amount)}
    end
    return ledger_summary(command, args, line, state)
end

local state = {day = 1, serial = 0, members = {}, currencies = {}, expenses = {}, used = {}, settlements = {}, budgets = {}}
local count = tonumber(io.read("l"))
for i = 1, count do
    local valid, output = pcall(execute, io.read("l"), state)
    if valid then
        for _, line in ipairs(output) do
            io.write(line, "\n")
        end
    else
        io.write("ERROR ", output, "\n")
    end
end
