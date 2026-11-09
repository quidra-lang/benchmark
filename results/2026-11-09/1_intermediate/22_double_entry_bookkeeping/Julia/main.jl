const Cents = Int64

struct CommandError <: Exception
    message::String
end
Base.showerror(io::IO, error::CommandError) = print(io, error.message)
fail(message::String) = throw(CommandError(message))
emit(parts...) = println(join(parts, " "))

@enum AccountType ASSET LIABILITY EQUITY REVENUE EXPENSE CONTRA_ASSET
@enum EntryCategory Journal Recurring Reversal Closing Reopen Depreciation Interest Writeoff
const ACCOUNT_TYPES = Dict(string(kind) => kind for kind in instances(AccountType))
normal_sign(kind::AccountType)::Cents = kind in (ASSET, EXPENSE) ? 1 : -1
type_family(kind::AccountType) = kind == CONTRA_ASSET ? ASSET : kind
category_text(category::EntryCategory) = lowercase(string(category))

function money(amount::Cents)
    whole, remainder = divrem(abs(amount), 100)
    return "$(amount < 0 ? "-" : "")$whole.$(lpad(string(remainder), 2, '0'))"
end

function parse_cents(text::String)
    parts = split(text, '.')
    return parse(Cents, parts[1]) * 100 + parse(Cents, parts[2])
end

leap(year::Int) = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)

function month_length(year::Int, month::Int)
    lengths = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
    return lengths[month] + (month == 2 && leap(year))
end

function day_number(year::Int, month::Int, day::Int)
    prior = year - 1
    result = 365 * prior + div(prior, 4) - div(prior, 100) + div(prior, 400) + day - 730120
    for m in 1:month-1
        result += month_length(year, m)
    end
    return result
end

function date_parts(number::Int)
    year = 2000
    while number >= 365 + leap(year)
        number -= 365 + leap(year)
        year += 1
    end
    month = 1
    while number >= month_length(year, month)
        number -= month_length(year, month)
        month += 1
    end
    return year, month, number + 1
end

function date_text(number::Int)
    year, month, day = date_parts(number)
    return "$(lpad(string(year), 4, '0'))-$(lpad(string(month), 2, '0'))-$(lpad(string(day), 2, '0'))"
end

function checked_date(text::String)
    year, month, day = parse.(Int, split(text, '-'))
    if !(2000 <= year <= 2099 && 1 <= month <= 12 && day >= 1)
        fail("invalid date $text")
    end
    day <= month_length(year, month) || fail("invalid date $text")
    return day_number(year, month, day)
end

function checked_range(first::String, last::String)
    start = checked_date(first)
    stop = checked_date(last)
    start <= stop || fail("invalid range $first $last")
    return start, stop
end

function months_after(number::Int, count::Int)
    year, month, day = date_parts(number)
    offset = month - 1 + count
    year += div(offset, 12)
    month = offset % 12 + 1
    return day_number(year, month, min(day, month_length(year, month)))
end

mutable struct Account
    code::String
    kind::AccountType
    name::String
    active::Bool
end

struct PostingLine
    debit::Bool
    code::String
    amount::Cents
    partner::Union{Nothing,String}
end
PostingLine(debit::Bool, code::String, amount::Cents) = PostingLine(debit, code, amount, nothing)
line_difference(line::PostingLine) = line.debit ? line.amount : -line.amount
line_codes(lines::Vector{PostingLine}) = [line.code for line in lines]

mutable struct Totals
    debit::Cents
    credit::Cents
end
Totals() = Totals(0, 0)

function line_totals(lines::Vector{PostingLine})
    debit = sum((line.amount for line in lines if line.debit); init=Cents(0))
    credit = sum((line.amount for line in lines if !line.debit); init=Cents(0))
    return Totals(debit, credit)
end

mutable struct Entry
    id::String
    day::Int
    category::EntryCategory
    memo::String
    lines::Vector{PostingLine}
    amount::Cents
    reversed_by::Union{Nothing,Int}
    reverses::Union{Nothing,Int}
end

mutable struct Template
    memo::String
    lines::Vector{PostingLine}
    uses::Int
end

mutable struct Draft
    journal::Bool
    key::String
    date_token::Union{Nothing,String}
    memo::String
    lines::Vector{PostingLine}
end

struct CloseRecord
    day::Int
    entry::Union{Nothing,Int}
end

mutable struct Books
    accounts::Dict{String,Account}
    entries::Vector{Entry}
    entry_positions::Dict{String,Int}
    templates::Dict{String,Template}
    draft::Union{Nothing,Draft}
    closes::Vector{CloseRecord}
    close_count::Int
    depreciation_count::Int
    interest_count::Int
    writeoff_count::Int
end

Books() = Books(Dict{String,Account}(), Entry[], Dict{String,Int}(), Dict{String,Template}(),
                nothing, CloseRecord[], 0, 0, 0, 0)
sorted_codes(books::Books) = sort!(collect(keys(books.accounts)))

function get_account(books::Books, code::String, required::Union{Nothing,AccountType}=nothing)
    account = get(books.accounts, code, nothing)
    account === nothing && fail("unknown account $code")
    if required !== nothing && account.kind != required
        fail("wrong type $code $required")
    end
    return account
end

function get_entry(books::Books, id::String)
    index = get(books.entry_positions, id, nothing)
    index === nothing && fail("unknown entry $id")
    return index
end

function get_template(books::Books, name::String)
    pattern = get(books.templates, name, nothing)
    pattern === nothing && fail("unknown template $name")
    return pattern
end

function active_check(books::Books, codes::Vector{String})
    for code in codes
        books.accounts[code].active || fail("inactive account $code")
    end
end

closed_text(books::Books) = isempty(books.closes) ? "none" : date_text(last(books.closes).day)

function check_closed(books::Books, day::Int)
    if !isempty(books.closes) && day <= last(books.closes).day
        fail("period closed $(date_text(day))")
    end
end

function ancestors(books::Books, code::String)
    return [other for other in sorted_codes(books) if other != code && startswith(code, other)]
end

function parent_code(books::Books, code::String)
    parents = ancestors(books, code)
    return isempty(parents) ? "none" : last(parents)
end

function top_account(books::Books, code::String)
    parents = ancestors(books, code)
    return isempty(parents) ? code : first(parents)
end

total_pair(totals::Dict{String,Totals}, code::String) = get(totals, code, Totals())

function difference(totals::Dict{String,Totals}, code::String)
    values = total_pair(totals, code)
    return values.debit - values.credit
end

function aggregate_entries(books::Books, first::Int=0, last::Int=36524; operating::Bool=false)
    totals = Dict{String,Totals}()
    for entry in books.entries
        if entry.day < first || entry.day > last || (operating && entry.category in (Closing, Reopen))
            continue
        end
        for line in entry.lines
            values = get!(totals, line.code, Totals())
            if line.debit
                values.debit += line.amount
            else
                values.credit += line.amount
            end
        end
    end
    return totals
end

function account_balance(books::Books, account::Account, day::Int=36524)
    return normal_sign(account.kind) * difference(aggregate_entries(books, 0, day), account.code)
end

function daily_sum(books::Books, account::Account, first::Int, last::Int)
    changes = zeros(Cents, last - first + 1)
    opening = Cents(0)
    for entry in books.entries
        entry.day > last && continue
        change = normal_sign(account.kind) * sum((line_difference(line) for line in entry.lines
                                                 if line.code == account.code); init=Cents(0))
        if entry.day < first
            opening += change
        else
            changes[entry.day - first + 1] += change
        end
    end
    return sum(cumsum(changes) .+ opening)
end

posting_order(books::Books) = sortperm(eachindex(books.entries); by=i -> (books.entries[i].day, i))

function post_entry!(books::Books, id::String, day::Int, category::EntryCategory, memo::String, lines::Vector{PostingLine})
    index = length(books.entries) + 1
    push!(books.entries, Entry(id, day, category, memo, copy(lines), line_totals(lines).debit, nothing, nothing))
    books.entry_positions[id] = index
    return index
end

function reverse_entry!(books::Books, index::Int, day::Int, category::EntryCategory, memo::String)
    original = books.entries[index]
    lines = [PostingLine(!line.debit, line.code, line.amount, line.partner) for line in original.lines]
    created = post_entry!(books, original.id * "-R", day, category, memo, lines)
    original.reversed_by = created
    books.entries[created].reverses = index
    return created
end

posted_text(entry::Entry) = "POST $(entry.id) $(date_text(entry.day)) lines $(length(entry.lines)) amount $(money(entry.amount))"

mutable struct OpenItem
    entry::Int
    original::Cents
    remaining::Cents
end

mutable struct Settlement
    items::Vector{OpenItem}
    head::Int
    unapplied::Cents
end
Settlement() = Settlement(OpenItem[], 1, 0)
open_items(group::Settlement) = @view group.items[group.head:end]

function settlements_for(books::Books, account::Account, day::Int)
    settlements = Dict{String,Settlement}()
    for index in posting_order(books)
        entry = books.entries[index]
        entry.day > day && break
        for line in entry.lines
            (line.code != account.code || line.partner === nothing) && continue
            group = get!(settlements, line.partner, Settlement())
            value = normal_sign(account.kind) * line_difference(line)
            if value > 0
                used = min(value, group.unapplied)
                group.unapplied -= used
                value > used && push!(group.items, OpenItem(index, value, value - used))
            else
                remaining = -value
                while remaining > 0 && group.head <= length(group.items)
                    item = group.items[group.head]
                    used = min(remaining, item.remaining)
                    item.remaining -= used
                    remaining -= used
                    item.remaining == 0 && (group.head += 1)
                end
                group.unapplied += remaining
            end
        end
    end
    return settlements
end

function section(books::Books, heading::String, kinds, sign::Cents, totals::Dict{String,Totals}; earnings::Union{Nothing,Cents}=nothing)
    selected = [code for code in sorted_codes(books) if books.accounts[code].kind in kinds]
    total = sign * sum((difference(totals, code) for code in selected); init=Cents(0))
    earnings !== nothing && (total += earnings)
    emit("  $heading", money(total))
    roots = sort!(unique([top_account(books, code) for code in selected]))
    for root in roots
        group = [code for code in selected if top_account(books, code) == root]
        values = [sign * difference(totals, code) for code in group]
        any(value -> value != 0, values) || continue
        emit("    $root", books.accounts[root].name, money(sum(values)))
        for (code, value) in zip(group, values)
            value != 0 && emit("      $code", books.accounts[code].name, money(value))
        end
    end
    earnings !== nothing && emit("    current earnings", money(earnings))
    return total
end

function aging_columns(values::Vector{Cents})
    return "0-30 $(money(values[1])) 31-60 $(money(values[2])) 61-90 $(money(values[3])) 91+ $(money(values[4])) unapplied $(money(values[5])) balance $(money(sum(values[1:4]) - values[5]))"
end

function post_draft!(books::Books)
    block = books.draft
    block === nothing && fail("no open entry")
    books.draft = nothing
    day = 0
    if block.journal
        haskey(books.entry_positions, block.key) && fail("duplicate entry $(block.key)")
        day = checked_date(block.date_token)
        check_closed(books, day)
    elseif haskey(books.templates, block.key)
        fail("duplicate template $(block.key)")
    end
    length(block.lines) >= 2 || fail("too few lines $(block.key)")
    for line in block.lines
        account = get_account(books, line.code)
        block.journal && !account.active && fail("inactive account $(line.code)")
        line.amount == 0 && fail("zero amount $(line.code)")
    end
    values = line_totals(block.lines)
    if values.debit != values.credit
        fail("unbalanced $(block.key) debit $(money(values.debit)) credit $(money(values.credit))")
    end
    if block.journal
        index = post_entry!(books, block.key, day, Journal, block.memo, block.lines)
        emit(posted_text(books.entries[index]))
    else
        books.templates[block.key] = Template(block.memo, copy(block.lines), 0)
        emit("TEMPLATE", block.key, "lines", length(block.lines), "amount", money(values.debit))
    end
end

function command!(books::Books, words::Vector{String})
    op = words[1]
    if op == "ACCOUNT"
        code = words[2]
        haskey(books.accounts, code) && fail("duplicate account $code")
        kind = ACCOUNT_TYPES[words[3]]
        for other in sorted_codes(books)
            if (startswith(code, other) || startswith(other, code)) && type_family(kind) != type_family(books.accounts[other].kind)
                fail("class mismatch $code $other")
            end
        end
        books.accounts[code] = Account(code, kind, words[4], true)
        emit("ACCOUNT", code, kind, words[4], "parent", parent_code(books, code))
    elseif op == "DEACTIVATE"
        account = get_account(books, words[2])
        account.active || fail("already inactive $(account.code)")
        balance = account_balance(books, account)
        balance == 0 || fail("nonzero balance $(account.code) $(money(balance))")
        account.active = false
        emit("DEACTIVATE", account.code, account.name)
    elseif op in ("JOURNAL", "TEMPLATE")
        if books.draft !== nothing
            emit("DISCARD", books.draft.key, "lines", length(books.draft.lines))
        end
        journal = op == "JOURNAL"
        books.draft = Draft(journal, words[2], journal ? words[3] : nothing,
                            journal ? words[4] : words[3], PostingLine[])
    elseif op in ("DR", "CR")
        books.draft === nothing && fail("no open entry")
        partner = length(words) == 4 ? words[4] : nothing
        push!(books.draft.lines, PostingLine(op == "DR", words[2], parse_cents(words[3]), partner))
    elseif op == "POST"
        post_draft!(books)
    elseif op == "DRAFT"
        block = books.draft
        block === nothing && fail("no open entry")
        amounts = line_totals(block.lines)
        emit("DRAFT", block.journal ? "journal" : "template", block.key, "lines", length(block.lines),
             "debit", money(amounts.debit), "credit", money(amounts.credit), "difference", money(amounts.debit - amounts.credit))
    elseif op == "REVERSE"
        index = get_entry(books, words[2])
        original = books.entries[index]
        original.category in (Reversal, Closing, Reopen) && fail("cannot reverse $(original.id)")
        original.reversed_by !== nothing && fail("already reversed $(original.id)")
        day = checked_date(words[3])
        day < original.day && fail("reverse before entry $(original.id) $(date_text(original.day))")
        check_closed(books, day)
        active_check(books, line_codes(original.lines))
        created = reverse_entry!(books, index, day, Reversal, original.memo)
        posted = books.entries[created]
        emit("REVERSE", original.id, "entry", posted.id, date_text(day), "amount", money(posted.amount))
    elseif op == "RECUR"
        pattern = get_template(books, words[2])
        day = checked_date(words[3])
        repeat_count = parse(Int, words[4])
        repeat_count == 0 && fail("invalid count")
        check_closed(books, day)
        active_check(books, line_codes(pattern.lines))
        emit("RECUR", words[2], "count", repeat_count)
        for offset in 0:repeat_count-1
            pattern.uses += 1
            id = "$(words[2])-$(pattern.uses)"
            index = post_entry!(books, id, months_after(day, offset), Recurring, pattern.memo, pattern.lines)
            emit("  " * posted_text(books.entries[index]))
        end
    elseif op == "DEPRECIATE"
        day = checked_date(words[2])
        check_closed(books, day)
        asset = get_account(books, words[3], ASSET)
        contra = get_account(books, words[4], CONTRA_ASSET)
        expense = get_account(books, words[5], EXPENSE)
        active_check(books, [contra.code, expense.code])
        cost = account_balance(books, asset, day)
        accumulated = account_balance(books, contra, day)
        amount = cost > 0 ? min(div(cost, parse(Int, words[6])), cost - accumulated) : Cents(0)
        amount <= 0 && fail("nothing to depreciate $(asset.code)")
        books.depreciation_count += 1
        id = "DEP-$(books.depreciation_count)"
        post_entry!(books, id, day, Depreciation, "depreciation",
                    [PostingLine(true, expense.code, amount), PostingLine(false, contra.code, amount)])
        emit("DEPRECIATE", asset.code, "entry", id, date_text(day), "amount", money(amount),
             "accumulated", money(accumulated + amount), "book", money(cost - accumulated - amount))
    elseif op == "INTEREST"
        account = get_account(books, words[2])
        account.kind in (ASSET, LIABILITY) || fail("not interest bearing $(account.code)")
        offset = get_account(books, words[3], account.kind == ASSET ? REVENUE : EXPENSE)
        first, last = checked_range(words[4], words[5])
        check_closed(books, last)
        active_check(books, [account.code, offset.code])
        total = daily_sum(books, account, first, last)
        amount = div(total * parse(Cents, words[6]), 3650000)
        amount <= 0 && fail("no interest $(account.code)")
        books.interest_count += 1
        id = "INT-$(books.interest_count)"
        debit = account.kind == ASSET ? account.code : offset.code
        credit = account.kind == ASSET ? offset.code : account.code
        post_entry!(books, id, last, Interest, "interest", [PostingLine(true, debit, amount), PostingLine(false, credit, amount)])
        days = last - first + 1
        emit("INTEREST", account.code, "entry", id, date_text(last), "days", days,
             "average", money(div(total, days)), "amount", money(amount))
    elseif op == "WRITEOFF"
        day = checked_date(words[2])
        check_closed(books, day)
        account = get_account(books, words[3], ASSET)
        expense = get_account(books, words[4], EXPENSE)
        active_check(books, [account.code, expense.code])
        age = parse(Int, words[5])
        settlements = settlements_for(books, account, day)
        targets = Tuple{String,Cents}[]
        for partner in sort!(collect(keys(settlements)))
            amount = sum((item.remaining for item in open_items(settlements[partner])
                          if day - books.entries[item.entry].day > age); init=Cents(0))
            amount > 0 && push!(targets, (partner, amount))
        end
        total = sum((amount for (_, amount) in targets); init=Cents(0))
        total == 0 && fail("nothing to write off $(account.code)")
        lines = [PostingLine(true, expense.code, total)]
        append!(lines, [PostingLine(false, account.code, amount, partner) for (partner, amount) in targets])
        books.writeoff_count += 1
        id = "WO-$(books.writeoff_count)"
        post_entry!(books, id, day, Writeoff, "writeoff", lines)
        emit("WRITEOFF", account.code, "entry", id, date_text(day), "partners", length(targets), "amount", money(total))
        for (partner, amount) in targets
            emit("  $partner", money(amount))
        end
    elseif op == "CLOSE"
        day = checked_date(words[2])
        check_closed(books, day)
        equity = get_account(books, words[3], EQUITY)
        active_check(books, [equity.code])
        totals = aggregate_entries(books, 0, day)
        selected = [code for code in sorted_codes(books)
                    if books.accounts[code].kind in (REVENUE, EXPENSE) && difference(totals, code) != 0]
        active_check(books, selected)
        lines = PostingLine[]
        for code in selected
            delta = difference(totals, code)
            push!(lines, PostingLine(delta < 0, code, abs(delta)))
        end
        income = -sum((difference(totals, code) for code in selected); init=Cents(0))
        income != 0 && push!(lines, PostingLine(income < 0, equity.code, abs(income)))
        books.close_count += 1
        index = nothing
        if !isempty(lines)
            id = "CLOSE-$(books.close_count)"
            index = post_entry!(books, id, day, Closing, "closing", lines)
            emit("CLOSE", date_text(day), "entry", id, "lines", length(lines), "net income", money(income))
        else
            emit("CLOSE", date_text(day), "no entry")
        end
        push!(books.closes, CloseRecord(day, index))
    elseif op == "REOPEN"
        isempty(books.closes) && fail("nothing to reopen")
        record = books.closes[end]
        detail = "no entry"
        if record.entry !== nothing
            active_check(books, line_codes(books.entries[record.entry].lines))
            created = reverse_entry!(books, record.entry, record.day, Reopen, "reopen")
            detail = "entry " * books.entries[created].id
        end
        pop!(books.closes)
        emit("REOPEN", date_text(record.day), detail, "closed", closed_text(books))
    elseif op == "LEDGER"
        account = get_account(books, words[2])
        first, last = checked_range(words[3], words[4])
        running = account_balance(books, account, first - 1)
        debit = credit = Cents(0)
        emit("LEDGER", account.code, account.name, date_text(first), date_text(last))
        emit("  opening", money(running))
        for index in posting_order(books)
            entry = books.entries[index]
            first <= entry.day <= last || continue
            for line in entry.lines
                line.code == account.code || continue
                running += normal_sign(account.kind) * line_difference(line)
                if line.debit
                    debit += line.amount
                else
                    credit += line.amount
                end
                emit("  $(date_text(entry.day))", entry.id, line.debit ? "DR" : "CR", money(line.amount), "balance", money(running), entry.memo)
            end
        end
        days = last - first + 1
        average = div(daily_sum(books, account, first, last), days)
        emit("  ending", money(running), "debits", money(debit), "credits", money(credit), "days", days, "average", money(average))
    elseif op == "ACTIVITY"
        account = get_account(books, words[2])
        year = parse(Int, words[3])
        debit = credit = Cents(0)
        emit("ACTIVITY", account.code, account.name, year)
        for month in 1:12
            first = day_number(year, month, 1)
            last = first + month_length(year, month) - 1
            amounts = total_pair(aggregate_entries(books, first, last), account.code)
            debit += amounts.debit
            credit += amounts.credit
            emit("  $year-$(lpad(string(month), 2, '0'))", "debit", money(amounts.debit), "credit", money(amounts.credit),
                 "balance", money(account_balance(books, account, last)))
        end
        emit("  total debit", money(debit), "credit", money(credit))
    elseif op == "TRIAL"
        day = checked_date(words[2])
        totals = aggregate_entries(books, 0, day)
        debit = credit = Cents(0)
        emit("TRIAL", date_text(day))
        for code in sorted_codes(books)
            delta = difference(totals, code)
            delta == 0 && continue
            emit("  $code", books.accounts[code].name, delta > 0 ? "debit" : "credit", money(abs(delta)))
            if delta > 0
                debit += delta
            else
                credit -= delta
            end
        end
        emit("  total debit", money(debit), "credit", money(credit))
    elseif op == "INCOME"
        first, last = checked_range(words[2], words[3])
        totals = aggregate_entries(books, first, last; operating=true)
        emit("INCOME", date_text(first), date_text(last))
        revenue = section(books, "REVENUE", (REVENUE,), Cents(-1), totals)
        expense = section(books, "EXPENSE", (EXPENSE,), Cents(1), totals)
        emit("  NET INCOME", money(revenue - expense))
    elseif op == "BALANCE"
        day = checked_date(words[2])
        totals = aggregate_entries(books, 0, day)
        earnings = -sum((difference(totals, code) for code in keys(books.accounts)
                         if books.accounts[code].kind in (REVENUE, EXPENSE)); init=Cents(0))
        emit("BALANCE", date_text(day))
        assets = section(books, "ASSETS", (ASSET, CONTRA_ASSET), Cents(1), totals)
        liabilities = section(books, "LIABILITIES", (LIABILITY,), Cents(-1), totals)
        equity = section(books, "EQUITY", (EQUITY,), Cents(-1), totals; earnings=earnings)
        if assets == liabilities + equity
            emit("  check ok")
        else
            emit("  check mismatch", money(assets - liabilities - equity))
        end
    elseif op == "ROLLUP"
        day = checked_date(words[3])
        selected = [code for code in sorted_codes(books) if startswith(code, words[2])]
        emit("ROLLUP", words[2], date_text(day))
        if isempty(selected)
            emit("  (none)")
            return nothing
        end
        totals = aggregate_entries(books, 0, day)
        debit = credit = Cents(0)
        for code in selected
            account = books.accounts[code]
            depth = count(other -> other != code && startswith(code, other), selected)
            subtotal = normal_sign(account.kind) * sum((difference(totals, other) for other in selected
                                                       if startswith(other, code)); init=Cents(0))
            padding = repeat(" ", 2 * (1 + depth))
            own = total_pair(totals, code)
            emit("$padding$code", account.name, "own", money(normal_sign(account.kind) * (own.debit - own.credit)), "total", money(subtotal))
            debit += own.debit
            credit += own.credit
        end
        emit("  postings debit", money(debit), "credit", money(credit))
    elseif op in ("AGING", "ITEMS")
        account = get_account(books, words[2])
        day = checked_date(words[end])
        settlements = settlements_for(books, account, day)
        if op == "ITEMS"
            group = get(settlements, words[3], Settlement())
            emit("ITEMS", account.code, account.name, words[3], date_text(day))
            items = open_items(group)
            for item in items
                entry = books.entries[item.entry]
                emit("  $(date_text(entry.day))", entry.id, "amount", money(item.original), "open", money(item.remaining), "age", day - entry.day)
            end
            balance = sum((item.remaining for item in items); init=Cents(0)) - group.unapplied
            emit("  unapplied", money(group.unapplied), "balance", money(balance))
        else
            emit("AGING", account.code, account.name, date_text(day))
            totals = zeros(Cents, 5)
            for partner in sort!(collect(keys(settlements)))
                group = settlements[partner]
                items = open_items(group)
                isempty(items) && group.unapplied == 0 && continue
                columns = zeros(Cents, 5)
                for item in items
                    age = day - books.entries[item.entry].day
                    bucket = age <= 30 ? 1 : age <= 60 ? 2 : age <= 90 ? 3 : 4
                    columns[bucket] += item.remaining
                end
                columns[5] = group.unapplied
                totals .+= columns
                emit("  $partner", aging_columns(columns))
            end
            emit("  total", aging_columns(totals))
        end
    elseif op == "ENTRY"
        entry = books.entries[get_entry(books, words[2])]
        emit("ENTRY", entry.id, date_text(entry.day), category_text(entry.category), entry.memo)
        for line in entry.lines
            detail = "$(line.debit ? "DR" : "CR") $(line.code) $(books.accounts[line.code].name) $(money(line.amount))"
            line.partner !== nothing && (detail *= " " * line.partner)
            emit("  " * detail)
        end
        emit("  total", money(entry.amount))
        entry.reverses !== nothing && emit("  reverses", books.entries[entry.reverses].id)
        entry.reversed_by !== nothing && emit("  reversed by", books.entries[entry.reversed_by].id)
    elseif op == "DAYBOOK"
        first, last = checked_range(words[2], words[3])
        entry_count = 0
        total = Cents(0)
        emit("DAYBOOK", date_text(first), date_text(last))
        for index in posting_order(books)
            entry = books.entries[index]
            first <= entry.day <= last || continue
            entry_count += 1
            total += entry.amount
            emit("  $(date_text(entry.day))", entry.id, category_text(entry.category), money(entry.amount), entry.memo)
        end
        emit("  total entries", entry_count, "amount", money(total))
    elseif op == "ACCOUNTS"
        emit("ACCOUNTS")
        isempty(books.accounts) && emit("  (none)")
        totals = aggregate_entries(books)
        for code in sorted_codes(books)
            account = books.accounts[code]
            emit("  $code", account.kind, account.name, "parent", parent_code(books, code),
                 "balance", money(normal_sign(account.kind) * difference(totals, code)), account.active ? "active" : "inactive")
        end
    elseif op == "TEMPLATES"
        emit("TEMPLATES")
        isempty(books.templates) && emit("  (none)")
        for name in sort!(collect(keys(books.templates)))
            pattern = books.templates[name]
            emit("  $name", pattern.memo, "lines", length(pattern.lines), "amount", money(line_totals(pattern.lines).debit), "used", pattern.uses)
        end
    elseif op == "STATUS"
        inactive = count(account -> !account.active, values(books.accounts))
        open = books.draft === nothing ? "none" : books.draft.key
        emit("STATUS accounts", length(books.accounts), "inactive", inactive, "entries", length(books.entries),
             "templates", length(books.templates), "closed", closed_text(books), "open", open)
    end
    return nothing
end

function main()
    count = parse(Int, readline())
    books = Books()
    for _ in 1:count
        words = String.(split(readline(), ' '))
        try
            command!(books, words)
        catch problem
            problem isa CommandError || rethrow()
            emit("ERROR", problem.message)
        end
    end
end

main()
