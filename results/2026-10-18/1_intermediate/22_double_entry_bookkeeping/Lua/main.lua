local LAST_DAY = 36524

local function fail(message) error({message = message}, 0) end
local function money(cents)
    local absolute = math.abs(cents)
    return (cents < 0 and "-" or "") .. string.format("%d.%02d", absolute // 100, absolute % 100)
end
local function parse_money(text)
    local whole, fraction = text:match("^(%d+)%.(%d%d)$")
    return tonumber(whole) * 100 + tonumber(fraction)
end
local function trunc_div(value, divisor)
    return value < 0 and -((-value) // divisor) or value // divisor
end
local function starts_with(text, prefix) return text:sub(1, #prefix) == prefix end
local function ascii_less(a, b)
    for i = 1, math.min(#a, #b) do
        local first, second = a:byte(i), b:byte(i)
        if first ~= second then return first < second end
    end
    return #a < #b
end
local function sorted_keys(values)
    local result = {}
    for key in pairs(values) do result[#result + 1] = key end
    table.sort(result, ascii_less)
    return result
end
local function normal(account) return (account.kind == "ASSET" or account.kind == "EXPENSE") and 1 or -1 end
local function type_class(kind) return kind == "CONTRA_ASSET" and "ASSET" or kind end
local function difference(line) return line.debit and line.amount or -line.amount end
local function new_line(debit, code, amount, partner)
    return {debit = debit, code = code, amount = amount, partner = partner}
end
local function line_totals(lines)
    local debit, credit = 0, 0
    for _, line in ipairs(lines) do
        if line.debit then debit = debit + line.amount else credit = credit + line.amount end
    end
    return debit, credit
end

local month_lengths = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
local function month_days(year, month)
    local leap = year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
    return month_lengths[month] + (month == 2 and leap and 1 or 0)
end
local function new_date(year, month, day)
    local prior = year - 1
    local number = 365 * (year - 2000) + prior // 4 - 1999 // 4 - prior // 100 + 1999 // 100 + prior // 400 - 1999 // 400
    for m = 1, month - 1 do number = number + month_days(year, m) end
    return {year = year, month = month, day = day, number = number + day - 1, text = string.format("%04d-%02d-%02d", year, month, day)}
end
local function parse_date(text)
    local year, month, day = tonumber(text:sub(1, 4)), tonumber(text:sub(6, 7)), tonumber(text:sub(9, 10))
    if year < 2000 or year > 2099 or month < 1 or month > 12 or day < 1 or day > month_days(year, month) then
        fail("invalid date " .. text)
    end
    return new_date(year, month, day)
end
local function date_range(first, last)
    local a = parse_date(first)
    local b = parse_date(last)
    if a.number > b.number then fail("invalid range " .. first .. " " .. last) end
    return a, b
end
local function add_months(date, count)
    local offset = date.month - 1 + count
    local year, month = date.year + offset // 12, offset % 12 + 1
    return new_date(year, month, math.min(date.day, month_days(year, month)))
end

local Books = {}
Books.__index = Books

function Books.new()
    return setmetatable({
        accounts = {}, account_order = {}, entries = {}, entry_ids = {}, templates = {}, template_order = {},
        closes = {}, close_count = 0, depreciation_count = 0, interest_count = 0, writeoff_count = 0, output = {},
    }, Books)
end

function Books:emit(format, ...) self.output[#self.output + 1] = string.format(format, ...) end
function Books:account(code)
    local account = self.accounts[code]
    if not account then fail("unknown account " .. code) end
    return account
end
function Books:entry(id)
    local entry = self.entry_ids[id]
    if not entry then fail("unknown entry " .. id) end
    return entry
end
function Books:typed_account(code, kind)
    local account = self:account(code)
    if account.kind ~= kind then fail("wrong type " .. code .. " " .. kind) end
    return account
end
function Books:active(accounts)
    for _, account in ipairs(accounts) do if not account.active then fail("inactive account " .. account.code) end end
end
function Books:active_lines(lines)
    for _, line in ipairs(lines) do self:active({self.accounts[line.code]}) end
end
function Books:closed() return #self.closes == 0 and "none" or self.closes[#self.closes].date.text end
function Books:check_closed(date)
    if #self.closes > 0 and date.number <= self.closes[#self.closes].date.number then fail("period closed " .. date.text) end
end
function Books:ordered_entries(first, last)
    first, last = first or 0, last or LAST_DAY
    local selected = {}
    for _, entry in ipairs(self.entries) do
        if entry.date.number >= first and entry.date.number <= last then selected[#selected + 1] = entry end
    end
    table.sort(selected, function(a, b)
        if a.date.number == b.date.number then return a.sequence < b.sequence end
        return a.date.number < b.date.number
    end)
    return selected
end
function Books:aggregate(first, last, operating)
    first, last = first or 0, last or LAST_DAY
    local result = {}
    for _, entry in ipairs(self.entries) do
        if entry.date.number >= first and entry.date.number <= last and
            not (operating and (entry.kind == "closing" or entry.kind == "reopen")) then
            for _, line in ipairs(entry.lines) do
                local total = result[line.code] or {debit = 0, credit = 0, difference = 0}
                result[line.code] = total
                if line.debit then total.debit = total.debit + line.amount else total.credit = total.credit + line.amount end
                total.difference = total.difference + difference(line)
            end
        end
    end
    return result
end
local function totals_for(totals, code) return totals[code] or {debit = 0, credit = 0, difference = 0} end
function Books:balance(account, last)
    last = last or LAST_DAY
    local value = 0
    for _, entry in ipairs(self.entries) do
        if entry.date.number <= last then
            for _, line in ipairs(entry.lines) do if line.code == account.code then value = value + difference(line) end end
        end
    end
    return value * normal(account)
end
function Books:daily_sum(account, first, last)
    local total = 0
    for _, entry in ipairs(self.entries) do
        if entry.date.number <= last then
            local change = 0
            for _, line in ipairs(entry.lines) do if line.code == account.code then change = change + difference(line) end end
            total = total + change * normal(account) * (last - math.max(first, entry.date.number) + 1)
        end
    end
    return total
end
function Books:parent(account)
    local parent
    for _, other in ipairs(self.account_order) do
        if other.code ~= account.code and starts_with(account.code, other.code) and
            (not parent or #other.code > #parent.code) then parent = other end
    end
    return parent
end
function Books:top(account)
    for _, other in ipairs(self.account_order) do if starts_with(account.code, other.code) then return other end end
end
function Books:post(id, date, kind, memo, lines)
    local saved = {}
    for i, line in ipairs(lines) do saved[i] = line end
    local amount = line_totals(saved)
    local entry = {id = id, date = date, kind = kind, memo = memo, lines = saved, sequence = #self.entries + 1, amount = amount}
    self.entries[#self.entries + 1] = entry
    self.entry_ids[id] = entry
    return entry
end
function Books:reverse(original, date, kind, memo)
    local lines = {}
    for i, line in ipairs(original.lines) do lines[i] = new_line(not line.debit, line.code, line.amount, line.partner) end
    local entry = self:post(original.id .. "-R", date, kind, memo, lines)
    original.reversed_by, entry.reverses = entry.id, original.id
    return entry
end
function Books:settlements(account, day)
    local result = {}
    for _, entry in ipairs(self:ordered_entries(0, day)) do
        for _, line in ipairs(entry.lines) do
            if line.code == account.code and line.partner ~= nil then
                local settlement = result[line.partner] or {items = {}, head = 1, unapplied = 0}
                result[line.partner] = settlement
                local signed = difference(line) * normal(account)
                if signed > 0 then
                    local applied = math.min(signed, settlement.unapplied)
                    settlement.unapplied = settlement.unapplied - applied
                    if signed > applied then
                        settlement.items[#settlement.items + 1] = {entry = entry, original = signed, remaining = signed - applied}
                    end
                else
                    local remaining = -signed
                    while remaining > 0 and settlement.head <= #settlement.items do
                        local item = settlement.items[settlement.head]
                        local applied = math.min(remaining, item.remaining)
                        item.remaining, remaining = item.remaining - applied, remaining - applied
                        if item.remaining == 0 then settlement.head = settlement.head + 1 end
                    end
                    settlement.unapplied = settlement.unapplied + remaining
                end
            end
        end
    end
    return result
end
function Books:section(heading, kinds, sign, totals, earnings)
    local groups, total = {}, earnings or 0
    for _, account in ipairs(self.account_order) do
        if kinds[account.kind] then
            local root = self:top(account)
            local group = groups[root.code] or {root = root, members = {}, total = 0, visible = false}
            groups[root.code] = group
            local amount = totals_for(totals, account.code).difference * sign
            group.members[#group.members + 1] = {account = account, amount = amount}
            group.total, group.visible = group.total + amount, group.visible or amount ~= 0
            total = total + amount
        end
    end
    self:emit("  %s %s", heading, money(total))
    for _, code in ipairs(sorted_keys(groups)) do
        local group = groups[code]
        if group.visible then
            self:emit("    %s %s %s", code, group.root.name, money(group.total))
            for _, member in ipairs(group.members) do
                if member.amount ~= 0 then self:emit("      %s %s %s", member.account.code, member.account.name, money(member.amount)) end
            end
        end
    end
    if earnings ~= nil then self:emit("    current earnings %s", money(earnings)) end
    return total
end
function Books:post_draft()
    local block = self.draft
    if not block then fail("no open entry") end
    self.draft = nil
    local date
    if block.kind == "journal" then
        if self.entry_ids[block.key] then fail("duplicate entry " .. block.key) end
        date = parse_date(block.date)
        self:check_closed(date)
    elseif self.templates[block.key] then fail("duplicate template " .. block.key) end
    if #block.lines < 2 then fail("too few lines " .. block.key) end
    for _, line in ipairs(block.lines) do
        local account = self:account(line.code)
        if block.kind == "journal" and not account.active then fail("inactive account " .. line.code) end
        if line.amount == 0 then fail("zero amount " .. line.code) end
    end
    local debit, credit = line_totals(block.lines)
    if debit ~= credit then fail(string.format("unbalanced %s debit %s credit %s", block.key, money(debit), money(credit))) end
    if block.kind == "journal" then
        local entry = self:post(block.key, date, "journal", block.memo, block.lines)
        self:emit("POST %s %s lines %d amount %s", entry.id, date.text, #entry.lines, money(entry.amount))
    else
        local template = {name = block.key, memo = block.memo, lines = block.lines, uses = 0}
        self.templates[block.key] = template
        self.template_order[#self.template_order + 1] = template
        table.sort(self.template_order, function(a, b) return ascii_less(a.name, b.name) end)
        self:emit("TEMPLATE %s lines %d amount %s", block.key, #block.lines, money(debit))
    end
end
function Books:close(date, code)
    self:check_closed(date)
    local equity = self:typed_account(code, "EQUITY")
    self:active({equity})
    local totals, targets = self:aggregate(0, date.number), {}
    for _, account in ipairs(self.account_order) do
        if (account.kind == "REVENUE" or account.kind == "EXPENSE") and totals_for(totals, account.code).difference ~= 0 then
            targets[#targets + 1] = account
        end
    end
    self:active(targets)
    local lines, income = {}, 0
    for _, account in ipairs(targets) do
        local value = totals[account.code].difference
        lines[#lines + 1] = new_line(value < 0, account.code, math.abs(value))
        income = income - value
    end
    if income ~= 0 then lines[#lines + 1] = new_line(income < 0, code, math.abs(income)) end
    self.close_count = self.close_count + 1
    local entry
    if #lines > 0 then entry = self:post("CLOSE-" .. self.close_count, date, "closing", "closing", lines) end
    self.closes[#self.closes + 1] = {date = date, entry = entry}
    if entry then self:emit("CLOSE %s entry %s lines %d net income %s", date.text, entry.id, #lines, money(income))
    else self:emit("CLOSE %s no entry", date.text) end
end
function Books:ledger(account, first, last)
    local running, debit, credit = self:balance(account, first.number - 1), 0, 0
    self:emit("LEDGER %s %s %s %s", account.code, account.name, first.text, last.text)
    self:emit("  opening %s", money(running))
    for _, entry in ipairs(self:ordered_entries(first.number, last.number)) do
        for _, line in ipairs(entry.lines) do
            if line.code == account.code then
                running = running + difference(line) * normal(account)
                if line.debit then debit = debit + line.amount else credit = credit + line.amount end
                self:emit("  %s %s %s %s balance %s %s", entry.date.text, entry.id, line.debit and "DR" or "CR", money(line.amount), money(running), entry.memo)
            end
        end
    end
    local days = last.number - first.number + 1
    self:emit("  ending %s debits %s credits %s days %d average %s", money(running), money(debit), money(credit), days, money(trunc_div(self:daily_sum(account, first.number, last.number), days)))
end
function Books:aging_line(name, values)
    local balance = values[1] + values[2] + values[3] + values[4] - values[5]
    self:emit("  %s 0-30 %s 31-60 %s 61-90 %s 91+ %s unapplied %s balance %s", name,
        money(values[1]), money(values[2]), money(values[3]), money(values[4]), money(values[5]), money(balance))
end

function Books:execute(words)
    local command = words[1]
    if command == "ACCOUNT" then
        local code, kind, name = words[2], words[3], words[4]
        if self.accounts[code] then fail("duplicate account " .. code) end
        for _, other in ipairs(self.account_order) do
            if (starts_with(code, other.code) or starts_with(other.code, code)) and type_class(kind) ~= type_class(other.kind) then
                fail("class mismatch " .. code .. " " .. other.code)
            end
        end
        local account = {code = code, kind = kind, name = name, active = true}
        self.accounts[code], self.account_order[#self.account_order + 1] = account, account
        table.sort(self.account_order, function(a, b) return ascii_less(a.code, b.code) end)
        local parent = self:parent(account)
        self:emit("ACCOUNT %s %s %s parent %s", code, kind, name, parent and parent.code or "none")
    elseif command == "DEACTIVATE" then
        local account = self:account(words[2])
        if not account.active then fail("already inactive " .. account.code) end
        local balance = self:balance(account)
        if balance ~= 0 then fail("nonzero balance " .. account.code .. " " .. money(balance)) end
        account.active = false
        self:emit("DEACTIVATE %s %s", account.code, account.name)
    elseif command == "JOURNAL" or command == "TEMPLATE" then
        if self.draft then self:emit("DISCARD %s lines %d", self.draft.key, #self.draft.lines) end
        self.draft = {kind = command == "JOURNAL" and "journal" or "template", key = words[2],
            date = command == "JOURNAL" and words[3] or nil, memo = command == "JOURNAL" and words[4] or words[3], lines = {}}
    elseif command == "DR" or command == "CR" then
        if not self.draft then fail("no open entry") end
        self.draft.lines[#self.draft.lines + 1] = new_line(command == "DR", words[2], parse_money(words[3]), words[4])
    elseif command == "POST" then
        self:post_draft()
    elseif command == "DRAFT" then
        local block = self.draft
        if not block then fail("no open entry") end
        local debit, credit = line_totals(block.lines)
        self:emit("DRAFT %s %s lines %d debit %s credit %s difference %s", block.kind, block.key, #block.lines, money(debit), money(credit), money(debit - credit))
    elseif command == "REVERSE" then
        local original = self:entry(words[2])
        if original.kind == "reversal" or original.kind == "closing" or original.kind == "reopen" then fail("cannot reverse " .. original.id) end
        if original.reversed_by then fail("already reversed " .. original.id) end
        local date = parse_date(words[3])
        if date.number < original.date.number then fail("reverse before entry " .. original.id .. " " .. original.date.text) end
        self:check_closed(date)
        self:active_lines(original.lines)
        local entry = self:reverse(original, date, "reversal", original.memo)
        self:emit("REVERSE %s entry %s %s amount %s", original.id, entry.id, date.text, money(entry.amount))
    elseif command == "RECUR" then
        local template = self.templates[words[2]]
        if not template then fail("unknown template " .. words[2]) end
        local date = parse_date(words[3])
        local count = tonumber(words[4])
        if count == 0 then fail("invalid count") end
        self:check_closed(date)
        self:active_lines(template.lines)
        self:emit("RECUR %s count %d", template.name, count)
        for month = 0, count - 1 do
            template.uses = template.uses + 1
            local entry = self:post(template.name .. "-" .. template.uses, add_months(date, month), "recurring", template.memo, template.lines)
            self:emit("  POST %s %s lines %d amount %s", entry.id, entry.date.text, #entry.lines, money(entry.amount))
        end
    elseif command == "DEPRECIATE" then
        local date = parse_date(words[2])
        self:check_closed(date)
        local asset = self:typed_account(words[3], "ASSET")
        local contra = self:typed_account(words[4], "CONTRA_ASSET")
        local expense = self:typed_account(words[5], "EXPENSE")
        self:active({contra, expense})
        local cost, accumulated = self:balance(asset, date.number), self:balance(contra, date.number)
        local amount = cost > 0 and math.min(cost // tonumber(words[6]), cost - accumulated) or 0
        if amount <= 0 then fail("nothing to depreciate " .. asset.code) end
        self.depreciation_count = self.depreciation_count + 1
        local entry = self:post("DEP-" .. self.depreciation_count, date, "depreciation", "depreciation", {
            new_line(true, expense.code, amount), new_line(false, contra.code, amount),
        })
        self:emit("DEPRECIATE %s entry %s %s amount %s accumulated %s book %s", asset.code, entry.id, date.text, money(amount), money(accumulated + amount), money(cost - accumulated - amount))
    elseif command == "INTEREST" then
        local account = self:account(words[2])
        if account.kind ~= "ASSET" and account.kind ~= "LIABILITY" then fail("not interest bearing " .. account.code) end
        local offset = self:typed_account(words[3], account.kind == "ASSET" and "REVENUE" or "EXPENSE")
        local first, last = date_range(words[4], words[5])
        self:check_closed(last)
        self:active({account, offset})
        local sum = self:daily_sum(account, first.number, last.number)
        local amount = trunc_div(sum * tonumber(words[6]), 3650000)
        if amount <= 0 then fail("no interest " .. account.code) end
        local debit = account.kind == "ASSET" and account.code or offset.code
        local credit = account.kind == "ASSET" and offset.code or account.code
        self.interest_count = self.interest_count + 1
        local entry = self:post("INT-" .. self.interest_count, last, "interest", "interest", {new_line(true, debit, amount), new_line(false, credit, amount)})
        local days = last.number - first.number + 1
        self:emit("INTEREST %s entry %s %s days %d average %s amount %s", account.code, entry.id, last.text, days, money(trunc_div(sum, days)), money(amount))
    elseif command == "WRITEOFF" then
        local date = parse_date(words[2])
        self:check_closed(date)
        local account = self:typed_account(words[3], "ASSET")
        local expense = self:typed_account(words[4], "EXPENSE")
        self:active({account, expense})
        local settlements = self:settlements(account, date.number)
        local targets, total = {}, 0
        for _, partner in ipairs(sorted_keys(settlements)) do
            local settlement, amount = settlements[partner], 0
            for i = settlement.head, #settlement.items do
                local item = settlement.items[i]
                if date.number - item.entry.date.number > tonumber(words[5]) then amount = amount + item.remaining end
            end
            if amount > 0 then targets[#targets + 1] = {partner = partner, amount = amount}; total = total + amount end
        end
        if total == 0 then fail("nothing to write off " .. account.code) end
        local lines = {new_line(true, expense.code, total)}
        for _, target in ipairs(targets) do lines[#lines + 1] = new_line(false, account.code, target.amount, target.partner) end
        self.writeoff_count = self.writeoff_count + 1
        local entry = self:post("WO-" .. self.writeoff_count, date, "writeoff", "writeoff", lines)
        self:emit("WRITEOFF %s entry %s %s partners %d amount %s", account.code, entry.id, date.text, #targets, money(total))
        for _, target in ipairs(targets) do self:emit("  %s %s", target.partner, money(target.amount)) end
    elseif command == "CLOSE" then
        self:close(parse_date(words[2]), words[3])
    elseif command == "REOPEN" then
        if #self.closes == 0 then fail("nothing to reopen") end
        local record, detail = self.closes[#self.closes], "no entry"
        if record.entry then
            self:active_lines(record.entry.lines)
            detail = "entry " .. self:reverse(record.entry, record.date, "reopen", "reopen").id
        end
        table.remove(self.closes)
        self:emit("REOPEN %s %s closed %s", record.date.text, detail, self:closed())
    elseif command == "LEDGER" then
        local account = self:account(words[2])
        local first, last = date_range(words[3], words[4])
        self:ledger(account, first, last)
    elseif command == "ACTIVITY" then
        local account = self:account(words[2])
        local year = tonumber(words[3])
        local debit, credit = 0, 0
        self:emit("ACTIVITY %s %s %d", account.code, account.name, year)
        for month = 1, 12 do
            local first, last = new_date(year, month, 1).number, new_date(year, month, month_days(year, month)).number
            local totals = totals_for(self:aggregate(first, last), account.code)
            debit, credit = debit + totals.debit, credit + totals.credit
            self:emit("  %04d-%02d debit %s credit %s balance %s", year, month, money(totals.debit), money(totals.credit), money(self:balance(account, last)))
        end
        self:emit("  total debit %s credit %s", money(debit), money(credit))
    elseif command == "TRIAL" then
        local date = parse_date(words[2])
        local totals = self:aggregate(0, date.number)
        local debit, credit = 0, 0
        self:emit("TRIAL %s", date.text)
        for _, account in ipairs(self.account_order) do
            local value = totals_for(totals, account.code).difference
            if value ~= 0 then
                if value > 0 then debit = debit + value else credit = credit - value end
                self:emit("  %s %s %s %s", account.code, account.name, value > 0 and "debit" or "credit", money(math.abs(value)))
            end
        end
        self:emit("  total debit %s credit %s", money(debit), money(credit))
    elseif command == "INCOME" then
        local first, last = date_range(words[2], words[3])
        local totals = self:aggregate(first.number, last.number, true)
        self:emit("INCOME %s %s", first.text, last.text)
        local revenue = self:section("REVENUE", {REVENUE = true}, -1, totals)
        local expense = self:section("EXPENSE", {EXPENSE = true}, 1, totals)
        self:emit("  NET INCOME %s", money(revenue - expense))
    elseif command == "BALANCE" then
        local date = parse_date(words[2])
        local totals, earnings = self:aggregate(0, date.number), 0
        for _, account in ipairs(self.account_order) do
            if account.kind == "REVENUE" or account.kind == "EXPENSE" then earnings = earnings - totals_for(totals, account.code).difference end
        end
        self:emit("BALANCE %s", date.text)
        local assets = self:section("ASSETS", {ASSET = true, CONTRA_ASSET = true}, 1, totals)
        local liabilities = self:section("LIABILITIES", {LIABILITY = true}, -1, totals)
        local equity = self:section("EQUITY", {EQUITY = true}, -1, totals, earnings)
        if assets == liabilities + equity then self:emit("  check ok")
        else self:emit("  check mismatch %s", money(assets - liabilities - equity)) end
    elseif command == "ROLLUP" then
        local date = parse_date(words[3])
        local targets = {}
        for _, account in ipairs(self.account_order) do if starts_with(account.code, words[2]) then targets[#targets + 1] = account end end
        self:emit("ROLLUP %s %s", words[2], date.text)
        if #targets == 0 then self:emit("  (none)"); return end
        local totals = self:aggregate(0, date.number)
        local debit, credit = 0, 0
        for _, account in ipairs(targets) do
            local depth, subtotal = 0, 0
            for _, other in ipairs(targets) do
                if other.code ~= account.code and starts_with(account.code, other.code) then depth = depth + 1 end
                if starts_with(other.code, account.code) then subtotal = subtotal + totals_for(totals, other.code).difference end
            end
            local own = totals_for(totals, account.code)
            debit, credit = debit + own.debit, credit + own.credit
            self:emit("%s%s %s own %s total %s", string.rep(" ", 2 * (1 + depth)), account.code, account.name, money(own.difference * normal(account)), money(subtotal * normal(account)))
        end
        self:emit("  postings debit %s credit %s", money(debit), money(credit))
    elseif command == "AGING" or command == "ITEMS" then
        local account = self:account(words[2])
        local date = parse_date(words[#words])
        local settlements = self:settlements(account, date.number)
        if command == "ITEMS" then
            local partner = words[3]
            local settlement = settlements[partner] or {items = {}, head = 1, unapplied = 0}
            self:emit("ITEMS %s %s %s %s", account.code, account.name, partner, date.text)
            local remaining = 0
            for i = settlement.head, #settlement.items do
                local item = settlement.items[i]
                remaining = remaining + item.remaining
                self:emit("  %s %s amount %s open %s age %d", item.entry.date.text, item.entry.id, money(item.original), money(item.remaining), date.number - item.entry.date.number)
            end
            self:emit("  unapplied %s balance %s", money(settlement.unapplied), money(remaining - settlement.unapplied))
        else
            self:emit("AGING %s %s %s", account.code, account.name, date.text)
            local total = {0, 0, 0, 0, 0}
            for _, partner in ipairs(sorted_keys(settlements)) do
                local settlement = settlements[partner]
                if settlement.head <= #settlement.items or settlement.unapplied > 0 then
                    local values = {0, 0, 0, 0, settlement.unapplied}
                    for i = settlement.head, #settlement.items do
                        local item = settlement.items[i]
                        local age = date.number - item.entry.date.number
                        local bucket = age <= 30 and 1 or age <= 60 and 2 or age <= 90 and 3 or 4
                        values[bucket] = values[bucket] + item.remaining
                    end
                    for i = 1, 5 do total[i] = total[i] + values[i] end
                    self:aging_line(partner, values)
                end
            end
            self:aging_line("total", total)
        end
    elseif command == "ENTRY" then
        local entry = self:entry(words[2])
        self:emit("ENTRY %s %s %s %s", entry.id, entry.date.text, entry.kind, entry.memo)
        for _, line in ipairs(entry.lines) do
            self:emit("  %s %s %s %s%s", line.debit and "DR" or "CR", line.code, self.accounts[line.code].name,
                money(line.amount), line.partner and (" " .. line.partner) or "")
        end
        self:emit("  total %s", money(entry.amount))
        if entry.reverses then self:emit("  reverses %s", entry.reverses) end
        if entry.reversed_by then self:emit("  reversed by %s", entry.reversed_by) end
    elseif command == "DAYBOOK" then
        local first, last = date_range(words[2], words[3])
        local selected, total = self:ordered_entries(first.number, last.number), 0
        self:emit("DAYBOOK %s %s", first.text, last.text)
        for _, entry in ipairs(selected) do
            total = total + entry.amount
            self:emit("  %s %s %s %s %s", entry.date.text, entry.id, entry.kind, money(entry.amount), entry.memo)
        end
        self:emit("  total entries %d amount %s", #selected, money(total))
    elseif command == "ACCOUNTS" then
        local totals = self:aggregate()
        self:emit("ACCOUNTS")
        for _, account in ipairs(self.account_order) do
            local parent = self:parent(account)
            self:emit("  %s %s %s parent %s balance %s %s", account.code, account.kind, account.name, parent and parent.code or "none",
                money(totals_for(totals, account.code).difference * normal(account)), account.active and "active" or "inactive")
        end
        if #self.account_order == 0 then self:emit("  (none)") end
    elseif command == "TEMPLATES" then
        self:emit("TEMPLATES")
        for _, template in ipairs(self.template_order) do
            local amount = line_totals(template.lines)
            self:emit("  %s %s lines %d amount %s used %d", template.name, template.memo, #template.lines, money(amount), template.uses)
        end
        if #self.template_order == 0 then self:emit("  (none)") end
    elseif command == "STATUS" then
        local inactive = 0
        for _, account in ipairs(self.account_order) do if not account.active then inactive = inactive + 1 end end
        self:emit("STATUS accounts %d inactive %d entries %d templates %d closed %s open %s", #self.account_order, inactive, #self.entries,
            #self.template_order, self:closed(), self.draft and self.draft.key or "none")
    end
end

local count = tonumber(io.read("l"))
local books = Books.new()
for _ = 1, count do
    local words = {}
    for word in io.read("l"):gmatch("%S+") do words[#words + 1] = word end
    local ok, problem = pcall(books.execute, books, words)
    if not ok then
        if type(problem) ~= "table" or not problem.message then error(problem) end
        books:emit("ERROR %s", problem.message)
    end
end
if #books.output > 0 then io.write(table.concat(books.output, "\n"), "\n") end
