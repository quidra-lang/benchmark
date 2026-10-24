package main

import (
    "bufio"
    "fmt"
    "os"
    "slices"
    "sort"
    "strconv"
    "strings"
)

const (
    available = iota
    loaned
    hold
    lostState
    withdrawn
)
var states = []string{"AVAILABLE", "LOANED", "HOLD", "LOST", "WITHDRAWN"}
var kinds = []string{"FINE", "FEE", "PRICE"}
type ref struct { title, copy int }
type bookCopy struct { state, member, from, due, renewals, expiry int }
type title struct {
    isbn, name, folded string
    price, borrowed int
    counts [5]int
    copies []bookCopy
    queue []int
}
type charge struct { day, kind, title, amount, unpaid int }
type member struct {
    id, kind, name string
    limit, period, rate, cap, reserveLimit, fee int
    balance, reservations int
    loans, holds []ref
    charges []charge
    history []string
}
type library struct {
    day, borrowed, returned, renewed, lost, paid, waived int
    charged [3]int
    closed map[int]bool
    titleIDs, memberIDs map[string]int
    titleOrder, memberOrder []int
    titles []*title
    members []*member
    output []string
}
func number(s string) int {
    n,_ := strconv.Atoi(s)
    return n
}
func money(n int) string { return fmt.Sprintf("%d.%02d", n/100, n%100) }
func cents(s string) int {
    whole,fraction,_ := strings.Cut(s,".")
    return number(whole)*100+number(fraction)
}
func normalize(input string) string {
    s := strings.ReplaceAll(input,"-","")
    if len(s) == 10 {
        sum := 0
        for i:=0; i<10; i++ {
            if !(s[i] >= '0' && s[i] <= '9') && !(i == 9 && s[i] == 'X') { return "" }
            value := int(s[i]-'0')
            if s[i] == 'X' { value = 10 }
            sum += (10-i)*value
        }
        if sum%11 != 0 { return "" }
        s = "978"+s[:9]
        sum = 0
        for i:=0; i<12; i++ {
            weight := 1
            if i%2 == 1 { weight = 3 }
            sum += weight*int(s[i]-'0')
        }
        return s+string(byte('0'+(10-sum%10)%10))
    }
    if len(s) != 13 || !(strings.HasPrefix(s,"978") || strings.HasPrefix(s,"979")) { return "" }
    sum := 0
    for i:=0; i<13; i++ {
        if s[i] < '0' || s[i] > '9' { return "" }
        weight := 1
        if i%2 == 1 { weight = 3 }
        sum += weight*int(s[i]-'0')
    }
    if sum%10 != 0 { return "" }
    return s
}
func (l *library) line(pattern string, args ...any) { l.output = append(l.output,fmt.Sprintf(pattern,args...)) }
func (l *library) error(condition bool, reason string) bool {
    if condition { l.line("ERROR %s",reason) }
    return condition
}
func (l *library) open(d int) int {
    for l.closed[d] { d++ }
    return d
}
func (l *library) copy(r ref) *bookCopy { return &l.titles[r.title].copies[r.copy] }
func (l *library) holdings(t int) int {
    c := l.titles[t].counts
    return c[0]+c[1]+c[2]
}
func (l *library) state(r ref, next int) {
    t := l.titles[r.title]
    t.counts[t.copies[r.copy].state]--
    t.copies[r.copy].state = next
    t.counts[next]++
}
func removeRef(refs []ref, r ref) []ref {
    if i := slices.Index(refs,r); i >= 0 { return slices.Delete(refs,i,i+1) }
    return refs
}
func findRef(refs []ref, t int) int {
    for _,r := range refs {
        if r.title == t { return r.copy }
    }
    return -1
}
func (l *library) getMember(id string) int {
    m,ok := l.memberIDs[id]
    if l.error(!ok,"unknown member") { return -1 }
    return m
}
func (l *library) getTitle(input string) int {
    isbn := normalize(input)
    if l.error(isbn == "","invalid isbn") { return -1 }
    t,ok := l.titleIDs[isbn]
    if l.error(!ok,"unknown book") { return -1 }
    return t
}
func (l *library) late(r ref) int {
    return max(0,l.day-l.copy(r).due)
}
func (l *library) fine(r ref) int {
    p := l.members[l.copy(r).member]
    return min(l.late(r)*p.rate,p.cap)
}
func (l *library) charge(m, kind, t, amount int) {
    if amount == 0 { return }
    p := l.members[m]
    p.charges = append(p.charges,charge{l.day,kind,t,amount,amount})
    p.balance += amount
    l.charged[kind] += amount
}
func (l *library) release(r ref) {
    t := l.titles[r.title]
    if len(t.queue) == 0 {
        l.state(r,available)
        return
    }
    m := t.queue[0]
    t.queue = t.queue[1:]
    l.state(r,hold)
    c := l.copy(r)
    c.member = m
    c.expiry = l.open(l.day+3)
    l.members[m].holds = append(l.members[m].holds,r)
    l.line("HOLD %s copy %d %s until %d",t.isbn,r.copy+1,l.members[m].id,c.expiry)
}
func (l *library) dropQueue(t int) {
    if l.holdings(t) != 0 { return }
    for _,m := range l.titles[t].queue {
        l.members[m].reservations--
        l.line("DROPPED %s %s",l.titles[t].isbn,l.members[m].id)
    }
    l.titles[t].queue = nil
}
func (l *library) endLoan(r ref, loss bool, heading string) {
    c := *l.copy(r)
    m,late,fine := c.member,l.late(r),l.fine(r)
    p,t := l.members[m],l.titles[r.title]
    p.loans = removeRef(p.loans,r)
    l.charge(m,0,r.title,fine)
    result := "RETURNED"
    if loss { result = "LOST" }
    history := fmt.Sprintf("%s %s copy %d from %d to %d late %d fine %s",result,t.isbn,r.copy+1,c.from,l.day,late,money(fine))
    if loss {
        history += " price "+money(t.price)
        l.charge(m,2,r.title,t.price)
        l.state(r,lostState)
        l.lost++
    } else { l.returned++ }
    p.history = append(p.history,history)
    s := fmt.Sprintf("%s %s %s copy %d late %d fine %s",heading,p.id,t.isbn,r.copy+1,late,money(fine))
    if loss { s += " price "+money(t.price) }
    l.line("%s balance %s",s,money(p.balance))
    if loss { l.dropQueue(r.title) } else { l.release(r) }
}
func (l *library) renewalReason(r ref) string {
    if l.late(r) != 0 { return "loan overdue" }
    if l.copy(r).renewals == 2 { return "renewal limit" }
    if len(l.titles[r.title].queue) != 0 { return "title reserved" }
    return ""
}
func (l *library) renew(r ref) {
    c := l.copy(r)
    p := l.members[c.member]
    c.due = l.open(l.day+p.period)
    c.renewals++
    l.renewed++
    l.line("RENEW %s %s copy %d due %d renewals %d",p.id,l.titles[r.title].isbn,r.copy+1,c.due,c.renewals)
}
func (l *library) ordered(refs []ref, holds bool) []ref {
    result := slices.Clone(refs)
    sort.Slice(result,func(i,j int) bool {
        a,b := result[i],result[j]
        x,y := l.copy(a).due,l.copy(b).due
        if holds { x,y = l.copy(a).expiry,l.copy(b).expiry }
        if x != y { return x < y }
        return l.titles[a.title].isbn < l.titles[b.title].isbn
    })
    return result
}
func (l *library) execute(a []string) {
    cmd := a[0]
    switch cmd {
    case "DAY":
        target := number(a[1])
        if l.error(target <= l.day,"invalid day") { return }
        l.line("DAY %d",target)
        for l.day < target {
            l.day++
            losses := []ref{}
            for _,id := range l.memberOrder {
                for _,r := range l.members[id].loans {
                    if l.copy(r).due+365 <= l.day { losses = append(losses,r) }
                }
            }
            for _,r := range losses { l.endLoan(r,true,"AUTOLOST") }
            expiries := []ref{}
            for _,t := range l.titleOrder {
                for i,c := range l.titles[t].copies {
                    if c.state == hold && c.expiry < l.day { expiries = append(expiries,ref{t,i}) }
                }
            }
            for _,r := range expiries {
                m := l.copy(r).member
                l.charge(m,1,r.title,l.members[m].fee)
                l.members[m].holds = removeRef(l.members[m].holds,r)
                l.members[m].reservations--
                l.line("EXPIRED %s copy %d %s fee %s",l.titles[r.title].isbn,r.copy+1,l.members[m].id,money(l.members[m].fee))
                l.release(r)
            }
        }
    case "CLOSED":
        d := number(a[1])
        if l.error(d <= l.day,"invalid day") || l.error(l.closed[d],"already closed") { return }
        l.closed[d] = true
        l.line("CLOSED %d",d)
        for _,id := range l.titleOrder {
            t := l.titles[id]
            for i := range t.copies {
                c := &t.copies[i]
                if c.state == loaned && c.due == d {
                    c.due = l.open(d)
                    l.line("MOVED %s copy %d %s due %d",t.isbn,i+1,l.members[c.member].id,c.due)
                } else if c.state == hold && c.expiry == d {
                    c.expiry = l.open(d)
                    l.line("MOVED %s copy %d %s until %d",t.isbn,i+1,l.members[c.member].id,c.expiry)
                }
            }
        }
    case "ADDBOOK":
        isbn,name := normalize(a[1]),strings.Join(a[4:]," ")
        if l.error(isbn == "","invalid isbn") { return }
        t,exists := l.titleIDs[isbn]
        if l.error(exists && l.titles[t].name != name,"title mismatch") { return }
        if !exists {
            t = len(l.titles)
            l.titles = append(l.titles,&title{isbn:isbn,name:name,folded:strings.ToLower(name)})
            l.titleIDs[isbn] = t
            position := sort.Search(len(l.titleOrder),func(i int) bool { return l.titles[l.titleOrder[i]].isbn > isbn })
            l.titleOrder = slices.Insert(l.titleOrder,position,t)
        }
        book := l.titles[t]
        book.price = cents(a[3])
        start,added := len(book.copies),number(a[2])
        book.copies = append(book.copies,make([]bookCopy,added)...)
        book.counts[available] += added
        l.line("ADDBOOK %s added %d total %d",isbn,added,l.holdings(t))
        for i:=start; i<len(book.copies); i++ { l.release(ref{t,i}) }
    case "ADDMEMBER":
        _,exists := l.memberIDs[a[1]]
        if l.error(exists,"duplicate member") || l.error(a[2] != "STUDENT" && a[2] != "STAFF","unknown type") { return }
        m := &member{id:a[1],kind:a[2],name:strings.Join(a[3:]," "),limit:3,period:14,rate:25,cap:1000,reserveLimit:2,fee:50}
        if m.kind == "STAFF" { m.limit,m.period,m.rate,m.cap,m.reserveLimit,m.fee = 10,28,10,2000,5,100 }
        id := len(l.members)
        l.memberIDs[m.id] = id
        l.members = append(l.members,m)
        position := sort.Search(len(l.memberOrder),func(i int) bool { return l.members[l.memberOrder[i]].id > m.id })
        l.memberOrder = slices.Insert(l.memberOrder,position,id)
        l.line("ADDMEMBER %s %s loans %d days %d",m.id,m.kind,m.limit,m.period)
    case "WITHDRAW":
        t := l.getTitle(a[1])
        if t < 0 { return }
        i := number(a[2])-1
        if l.error(i < 0 || i >= len(l.titles[t].copies),"unknown copy") { return }
        if l.error(l.titles[t].copies[i].state != available,"copy not available") { return }
        l.state(ref{t,i},withdrawn)
        l.line("WITHDRAW %s copy %d total %d",l.titles[t].isbn,i+1,l.holdings(t))
    case "BORROW","RETURN","RENEW","RESERVE","CANCEL","LOST":
        m := l.getMember(a[1])
        if m < 0 { return }
        t := l.getTitle(a[2])
        if t < 0 { return }
        p,book := l.members[m],l.titles[t]
        loan,held,q := findRef(p.loans,t),findRef(p.holds,t),slices.Index(book.queue,m)
        switch cmd {
        case "BORROW":
            if l.error(l.closed[l.day],"library closed") || l.error(loan >= 0,"already borrowed") || l.error(p.balance > 500,"member blocked") { return }
            overdue := false
            for _,r := range p.loans { overdue = overdue || l.late(r) != 0 }
            if l.error(overdue,"overdue loans") || l.error(len(p.loans) >= p.limit,"loan limit") { return }
            first := -1
            for i,c := range book.copies {
                if c.state == available {
                    first = i
                    break
                }
            }
            i := first
            if held >= 0 { i = held }
            reason := "no copy available"
            if book.counts[hold] > 0 { reason = "all copies on hold" }
            if l.error(i < 0,reason) { return }
            r := ref{t,i}
            if held >= 0 {
                p.holds = removeRef(p.holds,r)
                p.reservations--
            }
            l.state(r,loaned)
            *l.copy(r) = bookCopy{state:loaned,member:m,from:l.day,due:l.open(l.day+p.period)}
            p.loans = append(p.loans,r)
            sort.Slice(p.loans,func(i,j int) bool { return l.titles[p.loans[i].title].isbn < l.titles[p.loans[j].title].isbn })
            l.borrowed++
            book.borrowed++
            l.line("BORROW %s %s copy %d due %d",p.id,book.isbn,i+1,l.copy(r).due)
        case "RETURN","LOST","RENEW":
            if l.error(loan < 0,"not borrowed") { return }
            r := ref{t,loan}
            if cmd == "RENEW" {
                if l.error(p.balance > 500,"member blocked") { return }
                reason := l.renewalReason(r)
                if l.error(reason != "",reason) { return }
                l.renew(r)
            } else { l.endLoan(r,cmd == "LOST",cmd) }
        case "RESERVE":
            if l.error(loan >= 0,"already borrowed") || l.error(q >= 0 || held >= 0,"already reserved") || l.error(p.balance > 500,"member blocked") || l.error(p.reservations >= p.reserveLimit,"reservation limit") || l.error(l.holdings(t) == 0,"no copies") || l.error(book.counts[available] > 0,"copy available") { return }
            book.queue = append(book.queue,m)
            p.reservations++
            dues := []int{}
            for _,c := range book.copies {
                if c.state == loaned { dues = append(dues,c.due) }
            }
            sort.Ints(dues)
            position := len(book.queue)
            estimate := "none"
            if position <= len(dues) { estimate = strconv.Itoa(dues[position-1]) }
            l.line("RESERVE %s %s position %d estimate %s",p.id,book.isbn,position,estimate)
        case "CANCEL":
            if l.error(q < 0 && held < 0,"not reserved") { return }
            p.reservations--
            if q >= 0 {
                book.queue = slices.Delete(book.queue,q,q+1)
                l.line("CANCEL %s %s queue",p.id,book.isbn)
            } else {
                r := ref{t,held}
                p.holds = removeRef(p.holds,r)
                l.line("CANCEL %s %s hold copy %d",p.id,book.isbn,held+1)
                l.release(r)
            }
        }
    case "RENEWALL":
        m := l.getMember(a[1])
        if m < 0 { return }
        p := l.members[m]
        if l.error(len(p.loans) == 0,"no loans") || l.error(p.balance > 500,"member blocked") { return }
        good,skipped := 0,0
        for _,r := range p.loans {
            reason := l.renewalReason(r)
            if reason == "" {
                l.renew(r)
                good++
            } else {
                l.line("SKIP %s %s",l.titles[r.title].isbn,reason)
                skipped++
            }
        }
        l.line("RENEWALL %s renewed %d skipped %d",p.id,good,skipped)
    case "PAYFINE","WAIVE","FINES":
        m := l.getMember(a[1])
        if m < 0 { return }
        p := l.members[m]
        switch cmd {
        case "PAYFINE":
            if l.error(p.balance == 0,"no fines") { return }
            amount := cents(a[2])
            remaining := amount
            details := []string{}
            for i := range p.charges {
                c := &p.charges[i]
                applied := min(remaining,c.unpaid)
                if applied == 0 { continue }
                c.unpaid -= applied
                remaining -= applied
                details = append(details,fmt.Sprintf("ITEM %d %s paid %s remaining %s",i+1,kinds[c.kind],money(applied),money(c.unpaid)))
                if remaining == 0 { break }
            }
            p.balance -= amount-remaining
            l.paid += amount-remaining
            l.line("PAYFINE %s paid %s change %s balance %s",p.id,money(amount-remaining),money(remaining),money(p.balance))
            l.output = append(l.output,details...)
        case "WAIVE":
            i := number(a[2])-1
            if l.error(i < 0 || i >= len(p.charges),"unknown item") { return }
            c := &p.charges[i]
            if l.error(c.unpaid == 0,"item settled") { return }
            amount := c.unpaid
            c.unpaid = 0
            p.balance -= amount
            l.waived += amount
            l.line("WAIVE %s item %d %s amount %s balance %s",p.id,i+1,kinds[c.kind],money(amount),money(p.balance))
        case "FINES":
            count := 0
            for _,c := range p.charges {
                if c.unpaid > 0 { count++ }
            }
            l.line("FINES %s items %d balance %s",p.id,count,money(p.balance))
            for i,c := range p.charges {
                if c.unpaid > 0 { l.line("%d day %d %s %s amount %s remaining %s",i+1,c.day,kinds[c.kind],l.titles[c.title].isbn,money(c.amount),money(c.unpaid)) }
            }
        }
    case "SEARCH":
        keyword := strings.ToLower(strings.Join(a[1:]," "))
        found := []int{}
        for i,t := range l.titles {
            if strings.Contains(t.folded,keyword) { found = append(found,i) }
        }
        sort.Slice(found,func(i,j int) bool {
            a,b := l.titles[found[i]],l.titles[found[j]]
            if a.folded != b.folded { return a.folded < b.folded }
            return a.isbn < b.isbn
        })
        l.line("SEARCH %d",len(found))
        for _,id := range found {
            t := l.titles[id]
            l.line("%s %d/%d %s",t.isbn,t.counts[available],l.holdings(id),t.name)
        }
    case "OVERDUE":
        refs := []ref{}
        for _,m := range l.members {
            for _,r := range m.loans {
                if l.late(r) > 0 { refs = append(refs,r) }
            }
        }
        sort.Slice(refs,func(i,j int) bool {
            a,b := refs[i],refs[j]
            ca,cb := l.copy(a),l.copy(b)
            if ca.due != cb.due { return ca.due < cb.due }
            ma,mb := l.members[ca.member].id,l.members[cb.member].id
            if ma != mb { return ma < mb }
            return l.titles[a.title].isbn < l.titles[b.title].isbn
        })
        l.line("OVERDUE %d",len(refs))
        for _,r := range refs { l.line("%s %s copy %d due %d late %d fine %s",l.members[l.copy(r).member].id,l.titles[r.title].isbn,r.copy+1,l.copy(r).due,l.late(r),money(l.fine(r))) }
    case "NOTICES":
        notices := []string{}
        for _,id := range l.memberOrder {
            m := l.members[id]
            for _,r := range l.ordered(m.loans,false) {
                if l.copy(r).due > l.day+2 { continue }
                heading := "DUESOON"
                if l.late(r) > 0 { heading = "OVERDUE" }
                notices = append(notices,fmt.Sprintf("%s %s %s due %d",heading,m.id,l.titles[r.title].isbn,l.copy(r).due))
            }
            for _,r := range l.ordered(m.holds,true) { notices = append(notices,fmt.Sprintf("PICKUP %s %s until %d",m.id,l.titles[r.title].isbn,l.copy(r).expiry)) }
        }
        l.line("NOTICES %d",len(notices))
        l.output = append(l.output,notices...)
    case "MEMBER","MEMBERS","HISTORY":
        target := -1
        if cmd != "MEMBERS" {
            target = l.getMember(a[1])
            if target < 0 { return }
        }
        if cmd == "HISTORY" {
            m := l.members[target]
            l.line("HISTORY %s %d",m.id,len(m.history))
            l.output = append(l.output,m.history...)
            return
        }
        if cmd == "MEMBERS" { l.line("MEMBERS %d",len(l.members)) }
        for _,id := range l.memberOrder {
            if target >= 0 && id != target { continue }
            m := l.members[id]
            status := "OK"
            if m.balance > 500 { status = "BLOCKED" }
            if cmd == "MEMBERS" {
                l.line("%s %s loans %d reservations %d balance %s %s",m.id,m.kind,len(m.loans),m.reservations,money(m.balance),status)
                continue
            }
            l.line("MEMBER %s %s %s",m.id,m.kind,m.name)
            l.line("STATUS loans %d/%d reservations %d/%d balance %s %s",len(m.loans),m.limit,m.reservations,m.reserveLimit,money(m.balance),status)
            for _,r := range l.ordered(m.loans,false) {
                s := fmt.Sprintf("LOAN %s copy %d due %d renewals %d",l.titles[r.title].isbn,r.copy+1,l.copy(r).due,l.copy(r).renewals)
                if l.late(r) > 0 { s += fmt.Sprintf(" late %d fine %s",l.late(r),money(l.fine(r))) }
                l.line("%s",s)
            }
            for _,r := range l.ordered(m.holds,true) { l.line("HOLD %s copy %d until %d",l.titles[r.title].isbn,r.copy+1,l.copy(r).expiry) }
            for _,t := range l.titleOrder {
                q := slices.Index(l.titles[t].queue,id)
                if q >= 0 { l.line("QUEUE %s position %d",l.titles[t].isbn,q+1) }
            }
        }
    case "BOOK":
        t := l.getTitle(a[1])
        if t < 0 { return }
        book := l.titles[t]
        l.line("BOOK %s %s",book.isbn,book.name)
        l.line("PRICE %s copies %d borrowed %d",money(book.price),l.holdings(t),book.borrowed)
        for i,c := range book.copies {
            s := fmt.Sprintf("COPY %d %s",i+1,states[c.state])
            if c.state == loaned { s += fmt.Sprintf(" %s due %d",l.members[c.member].id,c.due) } else if c.state == hold { s += fmt.Sprintf(" %s until %d",l.members[c.member].id,c.expiry) }
            l.line("%s",s)
        }
        q := fmt.Sprintf("QUEUE %d",len(book.queue))
        for _,m := range book.queue { q += " "+l.members[m].id }
        l.line("%s",q)
    case "INVENTORY":
        totals := [5]int{}
        for _,t := range l.titles {
            for i,n := range t.counts { totals[i] += n }
        }
        l.line("INVENTORY titles %d copies %d available %d loaned %d hold %d lost %d withdrawn %d",len(l.titles),totals[0]+totals[1]+totals[2],totals[0],totals[1],totals[2],totals[3],totals[4])
        for _,id := range l.titleOrder {
            t := l.titles[id]
            l.line("%s copies %d available %d loaned %d hold %d queue %d",t.isbn,l.holdings(id),t.counts[0],t.counts[1],t.counts[2],len(t.queue))
        }
    case "STATS":
        active,outstanding := 0,0
        for _,m := range l.members {
            active += len(m.loans)
            outstanding += m.balance
        }
        l.line("STATS day %d titles %d members %d closed %d",l.day,len(l.titles),len(l.members),len(l.closed))
        l.line("LOANS borrowed %d returned %d renewed %d lost %d active %d",l.borrowed,l.returned,l.renewed,l.lost,active)
        l.line("MONEY fines %s fees %s charges %s paid %s waived %s outstanding %s",money(l.charged[0]),money(l.charged[1]),money(l.charged[2]),money(l.paid),money(l.waived),money(outstanding))
        top := []int{}
        for i,t := range l.titles {
            if t.borrowed > 0 { top = append(top,i) }
        }
        sort.Slice(top,func(i,j int) bool {
            a,b := l.titles[top[i]],l.titles[top[j]]
            if a.borrowed != b.borrowed { return a.borrowed > b.borrowed }
            return a.isbn < b.isbn
        })
        for i,id := range top {
            if i == 3 { break }
            l.line("TOP %d %s %d %s",i+1,l.titles[id].isbn,l.titles[id].borrowed,l.titles[id].name)
        }
    }
}
func main() {
    l := library{day:1,closed:map[int]bool{},titleIDs:map[string]int{},memberIDs:map[string]int{}}
    scanner := bufio.NewScanner(os.Stdin)
    scanner.Scan()
    count := number(scanner.Text())
    out := bufio.NewWriter(os.Stdout)
    defer out.Flush()
    for i:=0; i<count; i++ {
        scanner.Scan()
        l.output = nil
        l.execute(strings.Split(scanner.Text()," "))
        for _,line := range l.output { fmt.Fprintln(out,line) }
    }
}
