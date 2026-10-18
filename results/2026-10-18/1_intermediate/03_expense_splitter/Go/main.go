package main

import (
    "bufio"
    "fmt"
    "os"
    "sort"
    "strconv"
    "strings"
)

type member struct {
    name string
    active bool
    day int64
}
type part struct {
    member int
    value, result int64
}
type expense struct {
    id, currency, category, mode string
    day, serial, amount, total, interval, next, copies int64
    payers, participants []part
}
type settlement struct {
    from, to int
    amount, total, day, serial int64
    currency string
}
type transfer struct {
    from, to int
    amount int64
}
var members []member
var expenses []expense
var settlements []settlement
var currencies = map[string]int64{}
var budgets = map[string]int64{}
var used = map[string]bool{}
var currentDay int64 = 1
var serial int64

func fail(message string) { panic(message) }
func integer(s string) int64 {
    n, _ := strconv.ParseInt(s, 10, 64)
    return n
}
func amount(s string) int64 {
    a := strings.Split(s, ".")
    return integer(a[0])*100+integer(a[1])
}
func money(n int64) string { return fmt.Sprintf("%d.%02d", n/100, n%100) }
func signedMoney(n int64) string {
    if n > 0 { return "+"+money(n) }
    if n < 0 { return "-"+money(-n) }
    return "0.00"
}
func rateText(n int64) string { return fmt.Sprintf("%d.%04d", n/10000, n%10000) }
func percentage(p, w int64) string { return money(p*10000/w)+"%" }
func amountSpec(s string) (int64, string) {
    value, currency, _ := strings.Cut(s, "@")
    return amount(value), currency
}
func convert(value int64, currency string) int64 {
    if currency == "" { return value }
    rate, exists := currencies[currency]
    if !exists { fail("unknown currency "+currency) }
    return (value*rate+5000)/10000
}
func note(value int64, currency string) string {
    if currency == "" { return "" }
    return " ["+money(value)+" "+currency+"]"
}
func memberID(name string, active bool) int {
    for i, m := range members {
        if m.name == name {
            if active && !m.active { fail("inactive member "+name) }
            return i
        }
    }
    fail("unknown member "+name)
    return -1
}
func orderedMembers(active bool) []int {
    var order []int
    for i, m := range members {
        if !active || m.active { order = append(order, i) }
    }
    sort.Slice(order, func(i, j int) bool { return members[order[i]].name < members[order[j]].name })
    return order
}
func expenseID(id string) int {
    for i, e := range expenses {
        if e.id == id { return i }
    }
    fail("unknown expense "+id)
    return -1
}
func checkFrozen(e expense) {
    for _, list := range [][]part{e.payers, e.participants} {
        for _, p := range list {
            if !members[p.member].active { fail("inactive member "+members[p.member].name) }
        }
    }
}
func allActive(e expense) bool {
    for _, list := range [][]part{e.payers, e.participants} {
        for _, p := range list {
            if !members[p.member].active { return false }
        }
    }
    return true
}
func distribute(total int64, weights []int64) []int64 {
    var sum int64
    for _, w := range weights { sum += w }
    result, remainders := make([]int64, len(weights)), make([]int64, len(weights))
    order := make([]int, len(weights))
    left := total
    for i, w := range weights {
        product := total*w
        result[i], remainders[i], order[i] = product/sum, product%sum, i
        left -= result[i]
    }
    sort.SliceStable(order, func(i, j int) bool { return remainders[order[i]] > remainders[order[j]] })
    for i := int64(0); i < left; i++ { result[order[i]]++ }
    return result
}
func equalDistribution(total int64, count int) []int64 {
    result := make([]int64, count)
    for i := range result {
        result[i] = total/int64(count)
        if int64(i) < total%int64(count) { result[i]++ }
    }
    return result
}
func contributions(e *expense) {
    var weights []int64
    for _, p := range e.payers { weights = append(weights, p.value) }
    values := distribute(e.total, weights)
    for i := range e.payers { e.payers[i].result = values[i] }
}
func compute(e *expense) {
    e.total = convert(e.amount, e.currency)
    var specified []int64
    var sum int64
    for _, p := range e.participants {
        specified = append(specified, p.value)
        sum += p.value
    }
    var portions []int64
    switch e.mode {
    case "EQUAL": portions = equalDistribution(e.amount, len(specified))
    case "EXACT": portions = specified
    case "ADJUST":
        portions = equalDistribution(e.amount-sum, len(specified))
        for i := range portions { portions[i] += specified[i] }
    default: portions = distribute(e.amount, specified)
    }
    shares := distribute(e.total, portions)
    for i := range e.participants { e.participants[i].result = shares[i] }
    contributions(e)
}
func draftExpense(a []string, previous *expense) expense {
    e := expense{}
    if previous != nil { e = *previous }
    payer := memberID(a[2], true)
    value, currency := amountSpec(a[3])
    total := convert(value, currency)
    if value == 0 || total == 0 { fail("invalid amount") }
    e.amount, e.currency, e.category, e.mode = value, currency, a[4], a[5]
    e.payers = []part{{payer, value, 0}}
    e.participants = nil
    if e.mode == "EQUAL" && a[6] == "ALL" {
        for _, i := range orderedMembers(true) { e.participants = append(e.participants, part{member: i}) }
    } else {
        seen := map[int]bool{}
        for _, item := range a[6:] {
            name, specified, found := strings.Cut(item, ":")
            id := memberID(name, true)
            if seen[id] { fail("duplicate member "+name) }
            seen[id] = true
            var value int64
            if found {
                if e.mode == "PERCENT" || e.mode == "SHARES" { value = integer(specified) } else { value = amount(specified) }
            }
            e.participants = append(e.participants, part{id, value, 0})
        }
    }
    var sum int64
    for _, p := range e.participants { sum += p.value }
    if e.mode == "EXACT" && sum != e.amount || e.mode == "PERCENT" && sum != 10000 || e.mode == "SHARES" && sum == 0 || e.mode == "ADJUST" && sum > e.amount { fail("splits do not add up") }
    compute(&e)
    return e
}
func net(e expense) []int64 {
    result := make([]int64, len(members))
    for _, p := range e.payers { result[p.member] += p.result }
    for _, p := range e.participants { result[p.member] -= p.result }
    return result
}
func involved(e expense, id int) bool {
    for _, list := range [][]part{e.payers, e.participants} {
        for _, p := range list {
            if p.member == id { return true }
        }
    }
    return false
}
func balances() []int64 {
    result := make([]int64, len(members))
    for _, e := range expenses {
        for i, v := range net(e) { result[i] += v }
    }
    for _, s := range settlements {
        result[s.from] += s.total
        result[s.to] -= s.total
    }
    return result
}
func debts() [][]int64 {
    result := make([][]int64, len(members))
    for i := range result { result[i] = make([]int64, len(members)) }
    order := orderedMembers(false)
    for _, e := range expenses {
        change := net(e)
        var borrowers, lenders []int
        for _, i := range order {
            if change[i] < 0 { borrowers = append(borrowers, i) }
            if change[i] > 0 { lenders = append(lenders, i) }
        }
        for i, j := 0, 0; i < len(borrowers) && j < len(lenders); {
            from, to := borrowers[i], lenders[j]
            value := min(-change[from], change[to])
            result[from][to] += value
            change[from] += value
            change[to] -= value
            if change[from] == 0 { i++ }
            if change[to] == 0 { j++ }
        }
    }
    for _, s := range settlements { result[s.from][s.to] -= s.total }
    for i := range result {
        for j := i+1; j < len(result); j++ {
            value := result[i][j]-result[j][i]
            result[i][j], result[j][i] = value, -value
        }
    }
    return result
}
func spent(category string) int64 {
    var total int64
    for _, e := range expenses {
        if e.category == category { total += e.total }
    }
    return total
}
func warning(e expense) []string {
    budget, exists := budgets[e.category]
    total := spent(e.category)
    if exists && total > budget { return []string{"  WARNING "+e.category+" over budget by "+money(total-budget)} }
    return nil
}
func partsText(parts []part) string {
    var result []string
    for _, p := range parts { result = append(result, members[p.member].name+" "+money(p.result)) }
    return strings.Join(result, " + ")
}
func chronological() []int {
    order := make([]int, len(expenses))
    for i := range order { order[i] = i }
    sort.Slice(order, func(i, j int) bool {
        x, y := expenses[order[i]], expenses[order[j]]
        if x.day != y.day { return x.day < y.day }
        return x.serial < y.serial
    })
    return order
}
func greedy(group []int, original []int64) []transfer {
    values := append([]int64(nil), original...)
    var result []transfer
    for {
        from, to := -1, -1
        for _, i := range group {
            if values[i] < 0 && (from < 0 || values[i] < values[from]) { from = i }
            if values[i] > 0 && (to < 0 || values[i] > values[to]) { to = i }
        }
        if from < 0 { break }
        value := min(-values[from], values[to])
        result = append(result, transfer{from, to, value})
        values[from] += value
        values[to] -= value
    }
    return result
}
func transferLines(transfers []transfer, indent string) []string {
    var result []string
    for _, t := range transfers { result = append(result, indent+members[t.from].name+" -> "+members[t.to].name+" "+money(t.amount)) }
    return result
}
func keys(m map[string]int64) []string {
    var result []string
    for k := range m { result = append(result, k) }
    sort.Strings(result)
    return result
}
func lexLess(a, b []int) bool {
    for i := 0; i < len(a) && i < len(b); i++ {
        if a[i] != b[i] { return a[i] < b[i] }
    }
    return len(a) < len(b)
}
func execute(line string) []string {
    a := strings.Split(line, " ")
    command := a[0]
    var out []string
    switch command {
    case "DAY":
        day := integer(a[1])
        if day <= currentDay { fail("invalid day "+a[1]) }
        out = append(out, "DAY "+a[1])
        for {
            selected := -1
            for i, e := range expenses {
                if e.interval > 0 && e.next <= day && (selected < 0 || e.next < expenses[selected].next || e.next == expenses[selected].next && e.serial < expenses[selected].serial) { selected = i }
            }
            if selected < 0 { break }
            original := &expenses[selected]
            if !allActive(*original) || convert(original.amount, original.currency) == 0 {
                out = append(out, "  CANCEL "+original.id)
                original.interval = 0
                continue
            }
            copy := *original
            copy.payers = append([]part(nil), original.payers...)
            copy.participants = append([]part(nil), original.participants...)
            copy.id = original.id+"#"+strconv.FormatInt(original.copies+2, 10)
            copy.day = original.next
            serial++
            copy.serial = serial
            copy.interval, copy.next, copy.copies = 0, 0, 0
            original.copies++
            original.next += original.interval
            compute(&copy)
            used[copy.id] = true
            expenses = append(expenses, copy)
            out = append(out, "  RECUR "+copy.id+" "+money(copy.total))
            out = append(out, warning(copy)...)
        }
        currentDay = day
    case "MEMBER":
        id := -1
        for i, m := range members {
            if m.name == a[1] { id = i }
        }
        if id >= 0 && members[id].active { fail("duplicate member "+a[1]) }
        action := "joined"
        if id < 0 { members = append(members, member{a[1], true, currentDay}) } else {
            members[id].active, members[id].day = true, currentDay
            action = "rejoined"
        }
        out = append(out, "MEMBER "+a[1]+" "+action)
    case "LEAVE":
        id := memberID(a[1], true)
        if balances()[id] != 0 { fail("member has a balance "+a[1]) }
        members[id].active, members[id].day = false, currentDay
        out = append(out, "LEAVE "+a[1])
    case "CURRENCY":
        value := integer(a[2])
        result := "CURRENCY "+a[1]+" "+rateText(value)
        if old, exists := currencies[a[1]]; exists { result += " was "+rateText(old) }
        currencies[a[1]] = value
        out = append(out, result)
    case "EXPENSE", "EDIT":
        id := -1
        if command == "EXPENSE" {
            if used[a[1]] { fail("duplicate id "+a[1]) }
        } else {
            id = expenseID(a[1])
            checkFrozen(expenses[id])
        }
        var previous *expense
        if id >= 0 { previous = &expenses[id] }
        e := draftExpense(a, previous)
        if id < 0 {
            e.id, e.day = a[1], currentDay
            serial++
            e.serial = serial
            used[e.id] = true
            expenses = append(expenses, e)
        } else { expenses[id] = e }
        out = append(out, command+" "+e.id+" "+money(e.total)+note(e.amount, e.currency)+" = "+partsText(e.participants))
        out = append(out, warning(e)...)
    case "PAYERS":
        id := expenseID(a[1])
        checkFrozen(expenses[id])
        var payers []part
        seen := map[int]bool{}
        var sum int64
        for _, item := range a[2:] {
            name, payment, _ := strings.Cut(item, ":")
            member := memberID(name, true)
            if seen[member] { fail("duplicate member "+name) }
            seen[member] = true
            value := amount(payment)
            sum += value
            payers = append(payers, part{member, value, 0})
        }
        e := &expenses[id]
        if sum != e.amount { fail("payers do not add up") }
        e.payers = payers
        contributions(e)
        out = append(out, "PAYERS "+e.id+" "+money(e.total)+note(e.amount, e.currency)+" = "+partsText(e.payers))
    case "DELETE":
        id := expenseID(a[1])
        checkFrozen(expenses[id])
        expenses = append(expenses[:id], expenses[id+1:]...)
        out = append(out, "DELETE "+a[1])
    case "RECURRING":
        e := &expenses[expenseID(a[1])]
        e.interval = integer(a[2])
        if e.interval > 0 {
            e.next = currentDay+e.interval
            out = append(out, fmt.Sprintf("RECURRING %s interval %d next %d", e.id, e.interval, e.next))
        } else { out = append(out, "RECURRING "+e.id+" stopped") }
    case "SETTLE":
        from, to := memberID(a[1], true), memberID(a[2], true)
        if from == to { fail("same member "+a[1]) }
        value, currency := amountSpec(a[3])
        total := convert(value, currency)
        if value == 0 || total == 0 { fail("invalid amount") }
        serial++
        settlements = append(settlements, settlement{from, to, value, total, currentDay, serial, currency})
        out = append(out, "SETTLE "+a[1]+" -> "+a[2]+" "+money(total)+note(value, currency))
    case "BUDGET":
        value := amount(a[2])
        if value > 0 {
            budgets[a[1]] = value
            out = append(out, "BUDGET "+a[1]+" "+money(value))
        } else {
            delete(budgets, a[1])
            out = append(out, "BUDGET "+a[1]+" removed")
        }
    case "BALANCES":
        out = append(out, "BALANCES")
        values := balances()
        for _, i := range orderedMembers(true) { out = append(out, "  "+members[i].name+" "+signedMoney(values[i])) }
    case "OWES":
        id := memberID(a[1], false)
        out = append(out, "OWES "+a[1])
        values := debts()
        for _, i := range orderedMembers(false) {
            if i == id || values[id][i] == 0 { continue }
            from, to := id, i
            if values[id][i] < 0 { from, to = i, id }
            out = append(out, "  "+members[from].name+" owes "+members[to].name+" "+money(values[from][to]))
        }
    case "HISTORY":
        id := memberID(a[1], false)
        type item struct {
            day, serial, change int64
            label string
        }
        var items []item
        for _, e := range expenses {
            if involved(e, id) { items = append(items, item{e.day, e.serial, net(e)[id], e.id}) }
        }
        for _, s := range settlements {
            if s.from == id || s.to == id {
                change := s.total
                if s.to == id { change = -change }
                items = append(items, item{s.day, s.serial, change, members[s.from].name+"->"+members[s.to].name})
            }
        }
        sort.Slice(items, func(i, j int) bool {
            if items[i].day != items[j].day { return items[i].day < items[j].day }
            return items[i].serial < items[j].serial
        })
        out = append(out, "HISTORY "+a[1])
        var running int64
        for _, item := range items {
            running += item.change
            out = append(out, fmt.Sprintf("  day %d %s %s balance %s", item.day, item.label, signedMoney(item.change), signedMoney(running)))
        }
    case "MATRIX":
        out = append(out, "MATRIX")
        order := orderedMembers(true)
        if len(order) == 0 {
            out = append(out, "  (none)")
            break
        }
        values := debts()
        l := 0
        for _, i := range order { l = max(l, len(members[i].name)) }
        w := l
        for _, i := range order {
            for _, j := range order {
                if i != j {
                    w = max(w, len(money(max(int64(0), values[i][j]))))
                }
            }
        }
        header := strings.Repeat(" ", l)
        for _, i := range order { header += fmt.Sprintf("  %*s", w, members[i].name) }
        out = append(out, header)
        for _, i := range order {
            row := fmt.Sprintf("%-*s", l, members[i].name)
            for _, j := range order {
                cell := "-"
                if i != j { cell = money(max(int64(0), values[i][j])) }
                row += fmt.Sprintf("  %*s", w, cell)
            }
            out = append(out, row)
        }
    case "CATEGORY":
        out = append(out, "CATEGORY")
        totals := map[string]int64{}
        var total int64
        for _, e := range expenses {
            totals[e.category] += e.total
            total += e.total
        }
        categories := keys(totals)
        sort.SliceStable(categories, func(i, j int) bool { return totals[categories[i]] > totals[categories[j]] })
        for _, category := range categories {
            out = append(out, "  "+category+" "+money(totals[category])+" "+percentage(totals[category], total))
            shares := make([]int64, len(members))
            for _, e := range expenses {
                if e.category == category {
                    for _, p := range e.participants {
                        shares[p.member] += p.result
                    }
                }
            }
            order := orderedMembers(false)
            sort.SliceStable(order, func(i, j int) bool { return shares[order[i]] > shares[order[j]] })
            for _, i := range order {
                if shares[i] != 0 { out = append(out, "    "+members[i].name+" "+money(shares[i])+" "+percentage(shares[i], totals[category])) }
            }
        }
    case "BUDGETS":
        out = append(out, "BUDGETS")
        for _, category := range keys(budgets) {
            s, b := spent(category), budgets[category]
            suffix := " left "+money(b-s)
            if s > b { suffix = " over "+money(s-b) }
            out = append(out, "  "+category+" spent "+money(s)+" budget "+money(b)+" used "+percentage(s, b)+suffix)
        }
    case "TOTALS":
        out = append(out, "TOTALS")
        paid, shares := make([]int64, len(members)), make([]int64, len(members))
        sent, received := make([]int64, len(members)), make([]int64, len(members))
        var expenseTotal, settlementTotal int64
        for _, e := range expenses {
            expenseTotal += e.total
            for _, p := range e.payers { paid[p.member] += p.result }
            for _, p := range e.participants { shares[p.member] += p.result }
        }
        for _, s := range settlements {
            settlementTotal += s.total
            sent[s.from] += s.total
            received[s.to] += s.total
        }
        for _, i := range orderedMembers(false) { out = append(out, "  "+members[i].name+" paid "+money(paid[i])+" share "+money(shares[i])+" sent "+money(sent[i])+" received "+money(received[i])) }
        for _, currency := range keys(currencies) {
            count := 0
            var original, base int64
            for _, e := range expenses {
                if e.currency == currency {
                    count++
                    original += e.amount
                    base += e.total
                }
            }
            if count > 0 { out = append(out, fmt.Sprintf("  currency %s expenses %d amount %s base %s", currency, count, money(original), money(base))) }
        }
        out = append(out, fmt.Sprintf("  expenses %d total %s settlements %d total %s", len(expenses), money(expenseTotal), len(settlements), money(settlementTotal)))
    case "MEMBERS":
        out = append(out, "MEMBERS")
        for _, i := range orderedMembers(false) {
            count := 0
            for _, e := range expenses {
                if involved(e, i) { count++ }
            }
            status := "left"
            if members[i].active { status = "active" }
            out = append(out, fmt.Sprintf("  %s %s day %d expenses %d", members[i].name, status, members[i].day, count))
        }
    case "EXPENSES":
        id := -1
        if a[1] == "MEMBER" { id = memberID(a[2], false) }
        out = append(out, line)
        count := 0
        var total int64
        for _, i := range chronological() {
            e := expenses[i]
            matches := a[1] == "ALL" || a[1] == "CATEGORY" && e.category == a[2] || a[1] == "MEMBER" && involved(e, id) || a[1] == "DAYS" && e.day >= integer(a[2]) && e.day <= integer(a[3])
            if !matches { continue }
            var names []string
            for _, p := range e.payers { names = append(names, members[p.member].name) }
            out = append(out, fmt.Sprintf("  day %d %s %s %s by %s", e.day, e.id, e.category, money(e.total), strings.Join(names, ",")))
            count++
            total += e.total
        }
        out = append(out, fmt.Sprintf("  count %d total %s", count, money(total)))
    case "PERIODS":
        k := integer(a[1])
        type group struct {
            count int
            total int64
        }
        groups := map[int64]group{}
        for _, e := range expenses {
            i := (e.day-1)/k
            g := groups[i]
            g.count++
            g.total += e.total
            groups[i] = g
        }
        var order []int64
        for i := range groups { order = append(order, i) }
        sort.Slice(order, func(i, j int) bool { return order[i] < order[j] })
        out = append(out, "PERIODS "+a[1])
        for _, i := range order { out = append(out, fmt.Sprintf("  days %d-%d expenses %d total %s", i*k+1, i*k+k, groups[i].count, money(groups[i].total))) }
    case "SHOW":
        e := expenses[expenseID(a[1])]
        out = append(out, "SHOW "+a[1], fmt.Sprintf("  day %d category %s mode %s total %s%s", e.day, e.category, e.mode, money(e.total), note(e.amount, e.currency)))
        for _, p := range e.payers { out = append(out, "  paid "+members[p.member].name+" "+money(p.result)) }
        var units int64
        for _, p := range e.participants { units += p.value }
        for _, p := range e.participants {
            suffix := ""
            switch e.mode {
            case "EXACT": suffix = " "+money(p.value)
            case "PERCENT": suffix = " "+money(p.value)+"%"
            case "SHARES": suffix = fmt.Sprintf(" %d/%d", p.value, units)
            case "ADJUST": suffix = " +"+money(p.value)
            }
            out = append(out, "  share "+members[p.member].name+" "+money(p.result)+suffix)
        }
        if e.interval > 0 { out = append(out, fmt.Sprintf("  recurring interval %d next %d", e.interval, e.next)) }
    case "SIMPLIFY":
        values := balances()
        var order []int
        for _, i := range orderedMembers(false) {
            if values[i] != 0 { order = append(order, i) }
        }
        if a[1] == "GREEDY" {
            transfers := greedy(order, values)
            out = append(out, fmt.Sprintf("SIMPLIFY GREEDY transfers %d", len(transfers)))
            out = append(out, transferLines(transfers, "  ")...)
        } else {
            n := len(order)
            if n > 12 { fail("too many members") }
            sums := make([]int64, 1<<n)
            for mask := 1; mask < 1<<n; mask++ {
                bit := 0
                for mask&(1<<bit) == 0 { bit++ }
                sums[mask] = sums[mask^(1<<bit)]+values[order[bit]]
            }
            memo := make([]int, 1<<n)
            for i := 1; i < len(memo); i++ { memo[i] = -1 }
            var best func(int) int
            best = func(mask int) int {
                if memo[mask] >= 0 { return memo[mask] }
                first, result := mask & -mask, 0
                for sub := mask; sub > 0; sub = (sub-1)&mask {
                    if sub&first != 0 && sums[sub] == 0 { result = max(result, 1+best(mask^sub)) }
                }
                memo[mask] = result
                return result
            }
            remaining := (1 << n) - 1
            groupCount := best(remaining)
            out = append(out, fmt.Sprintf("SIMPLIFY OPTIMAL transfers %d groups %d", n-groupCount, groupCount))
            for remaining > 0 {
                first, chosen := remaining & -remaining, 0
                var chosenList []int
                for sub := remaining; sub > 0; sub = (sub-1)&remaining {
                    if sub&first == 0 || sums[sub] != 0 || 1+best(remaining^sub) != best(remaining) { continue }
                    var list []int
                    for i := 0; i < n; i++ {
                        if sub&(1<<i) != 0 { list = append(list, i) }
                    }
                    if chosen == 0 || lexLess(list, chosenList) { chosen, chosenList = sub, list }
                }
                var group []int
                var names []string
                for _, i := range chosenList {
                    group = append(group, order[i])
                    names = append(names, members[order[i]].name)
                }
                out = append(out, "  group "+strings.Join(names, " "))
                out = append(out, transferLines(greedy(group, values), "    ")...)
                remaining ^= chosen
            }
        }
    }
    if strings.Contains(" BALANCES OWES HISTORY CATEGORY BUDGETS MEMBERS PERIODS ", " "+command+" ") && len(out) == 1 { out = append(out, "  (none)") }
    return out
}
func commandResult(line string) (result []string) {
    defer func() {
        if message := recover(); message != nil { result = []string{"ERROR "+message.(string)} }
    }()
    return execute(line)
}
func main() {
    scanner := bufio.NewScanner(os.Stdin)
    scanner.Buffer(make([]byte, 4096), 1048576)
    scanner.Scan()
    count, _ := strconv.Atoi(scanner.Text())
    output := bufio.NewWriter(os.Stdout)
    defer output.Flush()
    for i := 0; i < count && scanner.Scan(); i++ {
        for _, line := range commandResult(scanner.Text()) { fmt.Fprintln(output, line) }
    }
}
