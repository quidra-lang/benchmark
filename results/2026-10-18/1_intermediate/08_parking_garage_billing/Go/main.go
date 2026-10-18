package main

import (
    "bufio"
    "fmt"
    "os"
    "maps"
    "slices"
    "sort"
    "strconv"
    "strings"
)

var types = []string{"MOTORCYCLE", "CAR", "ECAR", "VAN", "BUS"}
var kinds = []string{"MOTO", "COMPACT", "LARGE", "EV"}
var preferences = [][]int{{0,1,2}, {1,2}, {3,1,2}, {2}, {2}}
type spot struct { level, number, kind, vehicle int; closed bool }
type vehicle struct {
    plate string
    kind, spot, entry, energy, charge, validation int
    paid bool
    payment, parking, night int
}
type waiting struct { plate string; kind, joined int }
type bill struct { parking, night, lost, charge, total, due int }
type record struct { entry, exit, kind, total int; location string; lost bool }
type counts struct { entries, exits, refused, revenue, stay int }
type revenue struct { exits, parking, night, lost, charge, total int }
type garage struct {
    now, peak, peakTime int
    rates, caps [5]int
    fees [3]int
    spots []spot
    levels [][]int
    vehicles []*vehicle
    queue []waiting
    parked, passes map[string]int
    histories map[string][]record
    totals [5]counts
    daily map[int][5]counts
    revenue [5]revenue
    output []string
}
func number(s string) int {
    value,_ := strconv.Atoi(s)
    return value
}
func timeText(t int) string { return fmt.Sprintf("%d-%02d:%02d",t/1440+1,t%1440/60,t%60) }
func duration(t int) string { return fmt.Sprintf("%d:%02d",t/60,t%60) }
func tenth(q int) string { return fmt.Sprintf("%d.%d",q/10,q%10) }
func (g *garage) line(pattern string, args ...any) { g.output = append(g.output,fmt.Sprintf(pattern,args...)) }
func (g *garage) error(condition bool, reason string) bool {
    if condition { g.line("ERROR %s",reason) }
    return condition
}
func (g *garage) label(s int) string { return fmt.Sprintf("L%d-%d",g.spots[s].level,g.spots[s].number) }
func (g *garage) location(v *vehicle) string {
    result := g.label(v.spot)
    if v.kind == 4 { result += fmt.Sprintf("..%d",g.spots[v.spot].number+2) }
    return result
}
func (g *garage) free(s int) bool { return !g.spots[s].closed && g.spots[s].vehicle < 0 }
func (g *garage) validPass(p string) bool {
    last,ok := g.passes[p]
    return ok && g.now/1440+1 <= last
}
func (g *garage) spotID(s string) int {
    levelText,numberText,_ := strings.Cut(s[1:],"-")
    level,n := number(levelText),number(numberText)
    if level > len(g.levels) || n > len(g.levels[level-1]) { return -1 }
    return g.levels[level-1][n-1]
}
func (g *garage) getVehicle(p string) int {
    id,ok := g.parked[p]
    if g.error(!ok,p+" is not parked") { return -1 }
    return id
}
func (g *garage) waiting(p string) int {
    return slices.IndexFunc(g.queue,func(w waiting) bool { return w.plate == p })
}
func preference(kind, spotKind int) int {
    return slices.Index(preferences[kind],spotKind)
}
func (g *garage) assign(kind int) int {
    if kind == 4 {
        for _,level := range g.levels {
            for j:=0; j+2<len(level); j++ {
                a,b,c := level[j],level[j+1],level[j+2]
                if g.spots[a].kind == 2 && g.spots[b].kind == 2 && g.spots[c].kind == 2 && g.free(a) && g.free(b) && g.free(c) { return a }
            }
        }
    } else {
        for _,k := range preferences[kind] {
            for i,s := range g.spots {
                if s.kind == k && g.free(i) { return i }
            }
        }
    }
    return -1
}
func (g *garage) occupy(id, s int) {
    v := g.vehicles[id]
    v.spot = s
    size := 1
    if v.kind == 4 { size = 3 }
    for i:=0; i<size; i++ { g.spots[s+i].vehicle = id }
}
func (g *garage) vacate(id int) {
    v := g.vehicles[id]
    size := 1
    if v.kind == 4 { size = 3 }
    for i:=0; i<size; i++ { g.spots[v.spot+i].vehicle = -1 }
}
func (g *garage) park(plate string, kind, s int) int {
    id := len(g.vehicles)
    g.vehicles = append(g.vehicles,&vehicle{plate:plate,kind:kind,spot:s,entry:g.now})
    g.parked[plate] = id
    g.occupy(id,s)
    g.totals[kind].entries++
    today := g.daily[g.now/1440+1]
    today[kind].entries++
    g.daily[g.now/1440+1] = today
    if len(g.parked) > g.peak {
        g.peak = len(g.parked)
        g.peakTime = g.now
    }
    return id
}
func (g *garage) refuse(kind, t int) {
    g.totals[kind].refused++
    today := g.daily[t/1440+1]
    today[kind].refused++
    g.daily[t/1440+1] = today
}
func (g *garage) giveups() {
    remaining := []waiting{}
    for _,w := range g.queue {
        if g.now-w.joined >= 30 {
            g.line("GIVEUP %s %s %s",w.plate,types[w.kind],timeText(w.joined+30))
            g.refuse(w.kind,w.joined+30)
        } else { remaining = append(remaining,w) }
    }
    g.queue = remaining
}
func (g *garage) processQueue() {
    remaining := []waiting{}
    for _,w := range g.queue {
        s := g.assign(w.kind)
        if s < 0 { remaining = append(remaining,w) } else {
            id := g.park(w.plate,w.kind,s)
            g.line("ADMIT %s %s %s waited %s",w.plate,types[w.kind],g.location(g.vehicles[id]),duration(g.now-w.joined))
        }
    }
    g.queue = remaining
}
func (g *garage) interval(v *vehicle, from, freeTime int) (int,int) {
    length := g.now-from
    if g.validPass(v.plate) || length <= freeTime { return 0,0 }
    parking := 0
    for i:=0; i*1440<length; i++ {
        minutes := min(length-i*1440,1440)
        if i == 0 { minutes -= freeTime }
        parking += min((minutes+29)/30*g.rates[v.kind],g.caps[v.kind])
    }
    return parking,(g.now/1440-from/1440)*g.fees[0]
}
func (g *garage) bill(v *vehicle, loss bool) bill {
    from,freeTime := v.entry,15+v.validation
    if v.paid { from,freeTime = v.payment,15 }
    p,n := g.interval(v,from,freeTime)
    due := p+n
    if v.paid {
        p += v.parking
        n += v.night
    }
    lost := 0
    if loss { lost = g.fees[1] }
    total := p+n+lost+v.charge
    if !v.paid { due = total }
    return bill{p,n,lost,v.charge,total,due}
}
func (g *garage) feeLine(heading string, v *vehicle, b bill) {
    g.line("%s %s %s stay %s parking %d night %d lost %d charge %d total %d due %d",heading,v.plate,g.location(v),duration(g.now-v.entry),b.parking,b.night,b.lost,b.charge,b.total,b.due)
}
func (g *garage) annotation(v *vehicle) string {
    s := ""
    if g.validPass(v.plate) { s += " PASS" }
    if v.validation > 0 { s += fmt.Sprintf(" VAL %d",v.validation) }
    if v.energy > 0 { s += fmt.Sprintf(" KWH %d",v.energy) }
    if v.paid { s += " PAID" }
    return s
}
func (g *garage) orderedVehicles() []int {
    ids := slices.Collect(maps.Values(g.parked))
    sort.Slice(ids,func(i,j int) bool { return g.vehicles[ids[i]].spot < g.vehicles[ids[j]].spot })
    return ids
}
func (g *garage) move(id,s int) {
    before := g.location(g.vehicles[id])
    g.vacate(id)
    g.occupy(id,s)
    g.line("MOVE %s %s -> %s",g.vehicles[id].plate,before,g.label(s))
}
func (g *garage) execute(a []string) {
    cmd := a[0]
    switch cmd {
    case "LEVEL":
        level := []int{}
        for k:=0; k<4; k++ {
            for range number(a[k+1]) {
                level = append(level,len(g.spots))
                g.spots = append(g.spots,spot{level:len(g.levels)+1,number:len(level),kind:k,vehicle:-1})
            }
        }
        g.levels = append(g.levels,level)
        g.line("LEVEL %d spots %d MOTO %s COMPACT %s LARGE %s EV %s",len(g.levels),len(level),a[1],a[2],a[3],a[4])
        g.processQueue()
    case "CLOSE","OPEN":
        s := g.spotID(a[1])
        if g.error(s < 0,"unknown spot "+a[1]) { return }
        spot := &g.spots[s]
        if cmd == "CLOSE" {
            if g.error(spot.closed,"spot "+a[1]+" is already closed") { return }
            if spot.vehicle >= 0 {
                g.error(true,"spot "+a[1]+" is occupied by "+g.vehicles[spot.vehicle].plate)
                return
            }
            spot.closed = true
        } else {
            if g.error(!spot.closed,"spot "+a[1]+" is not closed") { return }
            spot.closed = false
        }
        g.line("%s %s %s",cmd,a[1],kinds[spot.kind])
        if cmd == "OPEN" { g.processQueue() }
    case "RATE":
        kind := slices.Index(types,a[1])
        if g.error(kind < 0,"unknown type "+a[1]) { return }
        rate,cap := number(a[2]),number(a[3])
        if g.error(cap < rate,"cap below rate for "+a[1]) { return }
        g.rates[kind],g.caps[kind] = rate,cap
        g.line("RATE %s %d %d",a[1],rate,cap)
    case "FEE":
        item := slices.Index([]string{"NIGHT","LOST","KWH"},a[1])
        if g.error(item < 0,"unknown fee "+a[1]) { return }
        g.fees[item] = number(a[2])
        g.line("FEE %s %s",a[1],a[2])
    case "ENTER":
        kind := slices.Index(types,a[2])
        if g.error(kind < 0,"unknown type "+a[2]) { return }
        if id,ok := g.parked[a[1]]; ok {
            g.error(true,a[1]+" is already parked at "+g.location(g.vehicles[id]))
            return
        }
        if g.error(g.waiting(a[1]) >= 0,a[1]+" is already waiting") { return }
        s := g.assign(kind)
        if s >= 0 {
            id := g.park(a[1],kind,s)
            g.line("ENTER %s %s %s",a[1],a[2],g.location(g.vehicles[id]))
        } else if len(g.queue) < 3 {
            g.queue = append(g.queue,waiting{a[1],kind,g.now})
            g.line("WAIT %s %s %d",a[1],a[2],len(g.queue))
        } else {
            g.refuse(kind,g.now)
            g.line("FULL %s %s",a[1],a[2])
        }
    case "LEAVE":
        i := g.waiting(a[1])
        if g.error(i < 0,a[1]+" is not waiting") { return }
        g.line("LEAVE %s %s",a[1],types[g.queue[i].kind])
        g.queue = slices.Delete(g.queue,i,i+1)
    case "EXIT","PAY","QUOTE","CHARGE","VALIDATE","MOVE":
        id := g.getVehicle(a[1])
        if id < 0 { return }
        v := g.vehicles[id]
        switch cmd {
        case "EXIT":
            loss := len(a) == 3
            if g.error(loss && v.paid,a[1]+" has already paid") { return }
            b := g.bill(v,loss)
            g.feeLine("EXIT",v,b)
            g.histories[v.plate] = append(g.histories[v.plate],record{v.entry,g.now,v.kind,b.total,g.location(v),loss})
            all := &g.totals[v.kind]
            all.exits++
            all.stay += g.now-v.entry
            all.revenue += b.total
            today := g.daily[g.now/1440+1]
            today[v.kind].exits++
            today[v.kind].revenue += b.total
            g.daily[g.now/1440+1] = today
            r := &g.revenue[v.kind]
            r.exits++
            r.parking += b.parking
            r.night += b.night
            r.lost += b.lost
            r.charge += b.charge
            r.total += b.total
            g.vacate(id)
            delete(g.parked,v.plate)
            g.processQueue()
        case "QUOTE": g.feeLine("QUOTE",v,g.bill(v,false))
        case "PAY":
            if g.error(v.paid,a[1]+" has already paid") { return }
            b := g.bill(v,false)
            v.paid = true
            v.payment,v.parking,v.night = g.now,b.parking,b.night
            g.line("PAY %s parking %d night %d charge %d total %d",v.plate,b.parking,b.night,b.charge,b.total)
        case "CHARGE":
            if g.error(v.kind != 2,a[1]+" is not an electric car") || g.error(g.spots[v.spot].kind != 3,a[1]+" is not at a charger") || g.error(v.paid,a[1]+" has already paid") { return }
            energy := number(a[2])
            if g.error(v.energy+energy > 100,"charge limit exceeded for "+a[1]) { return }
            cost := energy*g.fees[2]
            v.energy += energy
            v.charge += cost
            g.line("CHARGE %s kwh %d cost %d stay_kwh %d stay_cost %d",v.plate,energy,cost,v.energy,v.charge)
        case "VALIDATE":
            if g.error(v.paid,a[1]+" has already paid") { return }
            minutes := number(a[2])
            if g.error(v.validation+minutes > 180,"validation limit exceeded for "+a[1]) { return }
            v.validation += minutes
            g.line("VALIDATE %s %d total %d",v.plate,minutes,v.validation)
        case "MOVE":
            if g.error(v.kind == 4,"bus "+a[1]+" cannot be moved") { return }
            s := g.spotID(a[2])
            if g.error(s < 0,"unknown spot "+a[2]) || g.error(s == v.spot,a[1]+" is already at "+a[2]) { return }
            if g.error(g.spots[s].closed,"spot "+a[2]+" is closed") { return }
            if g.spots[s].vehicle >= 0 {
                g.error(true,"spot "+a[2]+" is occupied by "+g.vehicles[g.spots[s].vehicle].plate)
                return
            }
            if g.error(preference(v.kind,g.spots[s].kind) < 0,types[v.kind]+" cannot use "+kinds[g.spots[s].kind]+" spot "+a[2]) { return }
            g.move(id,s)
            g.processQueue()
        }
    case "PASS":
        days := number(a[2])
        if g.validPass(a[1]) { g.passes[a[1]] += days } else { g.passes[a[1]] = g.now/1440+days }
        g.line("PASS %s until %d",a[1],g.passes[a[1]])
    case "UNPASS":
        if g.error(!g.validPass(a[1]),a[1]+" has no pass") { return }
        delete(g.passes,a[1])
        g.line("UNPASS %s",a[1])
    case "REBALANCE":
        ids,moved := g.orderedVehicles(),0
        for _,id := range ids {
            v := g.vehicles[id]
            if v.kind == 4 { continue }
            current := preference(v.kind,g.spots[v.spot].kind)
            if current == 0 { continue }
            s := g.assign(v.kind)
            if s >= 0 && preference(v.kind,g.spots[s].kind) < current {
                g.move(id,s)
                moved++
            }
        }
        g.line("REBALANCE %d",moved)
        g.processQueue()
    case "WHERE":
        if id,ok := g.parked[a[1]]; ok {
            v := g.vehicles[id]
            g.line("WHERE %s %s %s %s stay %s%s",a[1],g.location(v),types[v.kind],timeText(v.entry),duration(g.now-v.entry),g.annotation(v))
        } else if q := g.waiting(a[1]); q >= 0 { g.line("WHERE %s waiting %d",a[1],q+1) } else if records := g.histories[a[1]]; len(records) > 0 { g.line("WHERE %s gone %s",a[1],timeText(records[len(records)-1].exit)) } else { g.error(true,"unknown plate "+a[1]) }
    case "LIST","OVERSTAY":
        level := 0
        if cmd == "LIST" && len(a) == 2 { level = number(a[1]) }
        if g.error(level > len(g.levels),fmt.Sprintf("unknown level %d",level)) { return }
        ids := []int{}
        for _,id := range g.orderedVehicles() {
            v := g.vehicles[id]
            if level != 0 && g.spots[v.spot].level != level { continue }
            if cmd == "OVERSTAY" && g.now-v.entry < number(a[1])*60 { continue }
            ids = append(ids,id)
        }
        if cmd == "OVERSTAY" {
            sort.SliceStable(ids,func(i,j int) bool { return g.vehicles[ids[i]].entry < g.vehicles[ids[j]].entry })
            g.line("OVERSTAY %s %d",a[1],len(ids))
        } else { g.line("LIST %d",len(ids)) }
        for _,id := range ids {
            v := g.vehicles[id]
            suffix := g.annotation(v)
            if cmd == "OVERSTAY" { suffix = " stay "+duration(g.now-v.entry) }
            g.line("%s %s %s %s%s",g.location(v),v.plate,types[v.kind],timeText(v.entry),suffix)
        }
    case "MAP":
        g.line("MAP %d",len(g.levels))
        for i,level := range g.levels {
            symbols := ""
            for j,id := range level {
                if j > 0 && j%10 == 0 { symbols += " " }
                s := g.spots[id]
                c := "mcle"[s.kind]
                if s.closed { c = '#' } else if s.vehicle >= 0 { c -= 'a'-'A' }
                symbols += string(c)
            }
            g.line("L%d %s",i+1,symbols)
        }
    case "OCCUPANCY":
        g.line("OCCUPANCY vehicles %d waiting %d",len(g.parked),len(g.queue))
        allUsed,allAvailable := [4]int{},[4]int{}
        allClosed := 0
        for i,level := range g.levels {
            used,available := [4]int{},[4]int{}
            closed := 0
            for _,id := range level {
                s := g.spots[id]
                if s.closed { closed++ } else { available[s.kind]++ }
                if s.vehicle >= 0 { used[s.kind]++ }
            }
            s := fmt.Sprintf("L%d",i+1)
            for k:=0; k<4; k++ {
                s += fmt.Sprintf(" %s %d/%d",kinds[k],used[k],available[k])
                allUsed[k] += used[k]
                allAvailable[k] += available[k]
            }
            allClosed += closed
            g.line("%s closed %d",s,closed)
        }
        s,used,available := "TOTAL",0,0
        for k:=0; k<4; k++ {
            s += fmt.Sprintf(" %s %d/%d",kinds[k],allUsed[k],allAvailable[k])
            used += allUsed[k]
            available += allAvailable[k]
        }
        q := 0
        if available > 0 { q = used*1000/available }
        g.line("%s closed %d rate %s%%",s,allClosed,tenth(q))
    case "SIGN":
        freeCounts,buses := [4]int{},0
        for _,level := range g.levels {
            run := 0
            for _,id := range level {
                if g.free(id) { freeCounts[g.spots[id].kind]++ }
                if g.free(id) && g.spots[id].kind == 2 { run++ } else {
                    buses += run/3
                    run = 0
                }
            }
            buses += run/3
        }
        s := "SIGN"
        for k:=0; k<5; k++ {
            count := buses
            if k != 4 {
                count = 0
                for _,kind := range preferences[k] { count += freeCounts[kind] }
            }
            value := "FULL"
            if count > 0 { value = strconv.Itoa(count) }
            s += " "+types[k]+" "+value
        }
        g.line("%s",s)
    case "RATES":
        g.line("RATES")
        for k:=0; k<5; k++ { g.line("%s %d %d",types[k],g.rates[k],g.caps[k]) }
        g.line("NIGHT %d LOST %d KWH %d",g.fees[0],g.fees[1],g.fees[2])
    case "PASSES":
        plates := []string{}
        for p,last := range g.passes {
            if g.now/1440+1 <= last { plates = append(plates,p) }
        }
        sort.Strings(plates)
        g.line("PASSES %d",len(plates))
        for _,p := range plates {
            suffix := ""
            if _,ok := g.parked[p]; ok { suffix = " IN" }
            g.line("%s until %d%s",p,g.passes[p],suffix)
        }
    case "HISTORY":
        records := g.histories[a[1]]
        if g.error(len(records) == 0,"no history for "+a[1]) { return }
        total := 0
        for _,r := range records { total += r.total }
        g.line("HISTORY %s visits %d paid %d",a[1],len(records),total)
        for _,r := range records {
            suffix := ""
            if r.lost { suffix = " LOST" }
            g.line("%s %s %s %s %d%s",timeText(r.entry),timeText(r.exit),r.location,types[r.kind],r.total,suffix)
        }
    case "REVENUE":
        g.line("REVENUE")
        all := revenue{}
        for k:=0; k<=5; k++ {
            r,name := all,"TOTAL"
            if k < 5 { r,name = g.revenue[k],types[k] }
            g.line("%s exits %d parking %d night %d lost %d charge %d total %d",name,r.exits,r.parking,r.night,r.lost,r.charge,r.total)
            if k < 5 {
                all.exits += r.exits
                all.parking += r.parking
                all.night += r.night
                all.lost += r.lost
                all.charge += r.charge
                all.total += r.total
            }
        }
    case "DAILY","STATS":
        rows := g.totals
        if cmd == "DAILY" { rows = g.daily[number(a[1])] }
        all := counts{}
        for _,c := range rows {
            all.entries += c.entries
            all.exits += c.exits
            all.refused += c.refused
            all.revenue += c.revenue
            all.stay += c.stay
        }
        if cmd == "DAILY" { g.line("DAILY %s entries %d exits %d refused %d revenue %d",a[1],all.entries,all.exits,all.refused,all.revenue) } else {
            at := "-"
            if g.peak > 0 { at = timeText(g.peakTime) }
            g.line("STATS parked %d peak %d at %s",len(g.parked),g.peak,at)
        }
        limit := 6
        if cmd == "DAILY" { limit = 5 }
        for k:=0; k<limit; k++ {
            c,name := all,"ALL"
            if k < 5 { c,name = rows[k],types[k] }
            if cmd == "DAILY" { g.line("%s entries %d exits %d refused %d revenue %d",name,c.entries,c.exits,c.refused,c.revenue) } else {
                q := 0
                if c.exits > 0 { q = c.stay*10/c.exits }
                g.line("%s entries %d exits %d refused %d avg_stay %s",name,c.entries,c.exits,c.refused,tenth(q))
            }
        }
    }
}
func main() {
    g := garage{rates:[5]int{100,200,200,300,600},caps:[5]int{800,1600,1600,2400,4800},fees:[3]int{300,2000,30},parked:map[string]int{},passes:map[string]int{},histories:map[string][]record{},daily:map[int][5]counts{}}
    scanner := bufio.NewScanner(os.Stdin)
    scanner.Scan()
    count := number(scanner.Text())
    out := bufio.NewWriter(os.Stdout)
    defer out.Flush()
    for i:=0; i<count; i++ {
        scanner.Scan()
        a := strings.Split(scanner.Text()," ")
        hour,minute,_ := strings.Cut(a[1],":")
        g.now = (number(a[0])-1)*1440+number(hour)*60+number(minute)
        g.output = nil
        g.giveups()
        g.execute(a[2:])
        for _,line := range g.output { fmt.Fprintln(out,line) }
    }
}
