package main

import (
    "bufio"
    "fmt"
    "os"
    "sort"
    "strconv"
    "strings"
)

var policies = []string{"FIFO", "LRU", "LFU", "NRU", "AGING", "CLOCK", "ECLOCK", "WSCLOCK", "RANDOM", "OPT"}
type Settings struct {
    Page, Frames, TLB, Sets, Tick, Tau int
    Seed int64
    Policy, Scope, ASID string
}
type Page struct {
    PID, Number, Frame, Slot int
    RO, Locked, Seen bool
    R, M, Load, Last, Uses, Age int
}
type Process struct {
    PID int
    Pages []*Page
    Faults, Writes, Seg, Prot, Resident, Peak, Hand int
    Exited bool
    History []int
}
type Item struct {
    Kind string
    Words []string
    PID, Address int
    Op string
}
type Event struct {
    Kind string
    PID, Address, First, Last int
    Op string
    Locked bool
}
type Simulation struct {
    Config Settings
    Processes map[int]*Process
    Frames, Slots []*Page
    TLB [][]*Page
    Refs [][2]int
    Position, Time, Faults, Zeros, Swapins, Hits, Writes, Switches, LastPID, Hand int
    Random int64
    FaultHistory []int
}
func number(s string) int { n, _ := strconv.Atoi(s); return n }
func address(s string) int { n, _ := strconv.ParseInt(s[2:], 16, 64); return int(n) }
func contains(words []string, s string) bool {
    for _, word := range words { if word == s { return true } }
    return false
}
func fail(s string) { panic(s) }
func hex(n int) string { return fmt.Sprintf("0x%X", n) }
func label(p *Page) string { return fmt.Sprintf("P%d:%d", p.PID, p.Number) }
func ratio(x, y int) string {
    v := 0
    if y > 0 { v = 10000*x/y }
    return fmt.Sprintf("%d.%02d%%", v/100, v%100)
}
func settings(words []string) Settings {
    c := Settings{256, 4, 4, 1, 0, 8, 1, "FIFO", "GLOBAL", "OFF"}
    known := []string{"page", "frames", "tlb", "sets", "policy", "scope", "asid", "tick", "tau", "seed"}
    seen := map[string]bool{}
    for _, word := range words {
        kv := strings.SplitN(word, "=", 2)
        k, v := kv[0], kv[1]
        if !contains(known, k) { fail("unknown key " + k) }
        if seen[k] { fail("duplicate key " + k) }
        seen[k] = true
        n64, err := strconv.ParseInt(v, 10, 64)
        n := int(n64)
        valid := err == nil
        switch k {
        case "page": valid = valid && n >= 16 && n <= 4096 && n&(n-1) == 0; c.Page = n
        case "frames": valid = valid && n >= 1 && n <= 16; c.Frames = n
        case "tlb": valid = valid && n >= 1 && n <= 8; c.TLB = n
        case "sets": valid = valid && n >= 1 && n <= 8; c.Sets = n
        case "tick": valid = valid && n >= 0 && n <= 1000; c.Tick = n
        case "tau": valid = valid && n >= 1 && n <= 1000; c.Tau = n
        case "seed": valid = valid && n64 >= 1 && n64 <= 2147483646; c.Seed = n64
        case "policy": valid = contains(policies, v); c.Policy = v
        case "scope": valid = v == "GLOBAL" || v == "LOCAL"; c.Scope = v
        case "asid": valid = v == "ON" || v == "OFF"; c.ASID = v
        }
        if !valid { fail("invalid " + k) }
    }
    if c.TLB%c.Sets != 0 { fail("invalid sets") }
    return c
}
func newSimulation(c Settings, refs [][2]int) *Simulation {
    return &Simulation{Config:c, Processes:map[int]*Process{}, Frames:make([]*Page,c.Frames), TLB:make([][]*Page,c.Sets), Refs:refs, Random:c.Seed}
}
func (s *Simulation) pids() []int {
    ids := []int{}
    for id := range s.Processes { ids = append(ids,id) }
    sort.Ints(ids)
    return ids
}
func (s *Simulation) declare(pid, count int) {
    p := &Process{PID:pid}
    for n:=0; n<count; n++ { p.Pages = append(p.Pages,&Page{PID:pid,Number:n,Frame:-1,Slot:-1}) }
    s.Processes[pid] = p
}
func (s *Simulation) process(pid int) *Process {
    p, ok := s.Processes[pid]
    if !ok { fail(fmt.Sprintf("unknown process %d",pid)) }
    if p.Exited { fail(fmt.Sprintf("process %d exited",pid)) }
    return p
}
func (s *Simulation) quota(pid int) int {
    ids := s.pids()
    q, r := s.Config.Frames/len(ids), s.Config.Frames%len(ids)
    for i,id := range ids { if id == pid && i < r { return q+1 } }
    return q
}
func (s *Simulation) removeTLB(page *Page) {
    k := page.Number%s.Config.Sets
    entries := s.TLB[k][:0]
    for _,p := range s.TLB[k] { if p != page { entries=append(entries,p) } }
    s.TLB[k] = entries
}
func (s *Simulation) writeback(p *Page) {
    s.Writes++
    s.Processes[p.PID].Writes++
    p.M = 0
    if p.Slot < 0 {
        slot := 0
        for slot<len(s.Slots) && s.Slots[slot]!=nil { slot++ }
        if slot==len(s.Slots) { s.Slots=append(s.Slots,nil) }
        p.Slot=slot
        s.Slots[slot]=p
    }
}
func (s *Simulation) nextUse(p *Page) int {
    for i:=s.Position+1; i<len(s.Refs); i++ { if s.Refs[i]==[2]int{p.PID,p.Number} { return i } }
    return len(s.Refs)
}
func (s *Simulation) choose(proc *Process, candidates []int) int {
    c := s.Config
    if c.Policy=="RANDOM" {
        s.Random=s.Random*48271%2147483647
        return candidates[int(s.Random%int64(len(candidates)))]
    }
    if contains([]string{"CLOCK","ECLOCK","WSCLOCK"},c.Policy) {
        hand:=s.Hand
        if c.Scope=="LOCAL" { hand=proc.Hand }
        sort.Slice(candidates,func(i,j int)bool{return (candidates[i]-hand+c.Frames)%c.Frames<(candidates[j]-hand+c.Frames)%c.Frames})
        chosen:=-1
        switch c.Policy {
        case "CLOCK":
            for chosen<0 {
                for _,f:=range candidates {
                    p:=s.Frames[f]
                    if p.R==0 { chosen=f; break }
                    p.R=0
                }
            }
        case "ECLOCK":
            for chosen<0 {
                for _,f:=range candidates { p:=s.Frames[f]; if p.R==0&&p.M==0 { chosen=f; break } }
                if chosen>=0 { break }
                for _,f:=range candidates { p:=s.Frames[f]; if p.R==0&&p.M==1 { chosen=f; break }; p.R=0 }
            }
        case "WSCLOCK":
            for _,f:=range candidates {
                p:=s.Frames[f]
                if p.R==1 { p.R=0; p.Last=s.Time } else if s.Time-p.Last>c.Tau {
                    if p.M==0 { chosen=f; break }
                    s.writeback(p)
                }
            }
            if chosen<0 { for _,f:=range candidates { if s.Frames[f].M==0 { chosen=f; break } } }
            if chosen<0 { chosen=candidates[0] }
        }
        if c.Scope=="LOCAL" { proc.Hand=(chosen+1)%c.Frames } else { s.Hand=(chosen+1)%c.Frames }
        return chosen
    }
    rank:=func(f int)(int,int){
        p:=s.Frames[f]
        switch c.Policy {
        case "FIFO": return p.Load,f
        case "LRU": return p.Last,f
        case "LFU": return p.Uses,p.Load
        case "NRU": return 2*p.R+p.M,f
        case "AGING": return p.Age,p.Load
        default: return -s.nextUse(p),f
        }
    }
    best:=candidates[0]
    for _,f:=range candidates[1:] { a,b:=rank(f); x,y:=rank(best); if a<x||(a==x&&b<y) { best=f } }
    return best
}
func (s *Simulation) target(p *Process) int {
    global:=s.Config.Scope=="GLOBAL"
    if global || p.Resident<s.quota(p.PID) {
        for f,page:=range s.Frames { if page==nil { return f } }
    }
    candidates,unlocked:=[]int{},[]int{}
    for f,page:=range s.Frames {
        if page!=nil&&(global||page.PID==p.PID) {
            candidates=append(candidates,f)
            if !page.Locked { unlocked=append(unlocked,f) }
        }
    }
    if len(unlocked)>0 { candidates=unlocked }
    return s.choose(p,candidates)
}
func (s *Simulation) access(pid int, op string, addr, pos int) []string {
    s.Position=pos
    s.Time++
    p:=s.Processes[pid]
    switched:=s.LastPID!=0&&s.LastPID!=pid
    if switched { s.Switches++; if s.Config.ASID=="OFF" { s.TLB=make([][]*Page,s.Config.Sets) } }
    s.LastPID=pid
    n,offset:=addr/s.Config.Page,addr%s.Config.Page
    page:=p.Pages[n]
    k:=n%s.Config.Sets
    hit:=false
    for _,entry:=range s.TLB[k] { if entry==page { hit=true; break } }
    result:=""
    fault:=0
    if hit {
        s.Hits++
        result="TLBHIT"
        s.removeTLB(page)
    } else if page.Frame>=0 { result="HIT" } else {
        fault=1
        s.Faults++
        p.Faults++
        result="FAULT ZERO"
        if page.Slot>=0 { s.Swapins++; result="FAULT SWAPIN" } else { s.Zeros++ }
        f:=s.target(p)
        victim:=s.Frames[f]
        if victim!=nil {
            result+=" evict="+label(victim)
            victim.Frame=-1
            s.Processes[victim.PID].Resident--
            s.removeTLB(victim)
            if victim.M==1 { s.writeback(victim); result+=" writeback" }
        }
        s.Frames[f]=page
        page.Frame=f
        page.Load=s.Time
        page.Uses,page.M,page.Age=0,0,0
        p.Resident++
        if p.Resident>p.Peak { p.Peak=p.Resident }
    }
    entries:=s.TLB[k]
    if len(entries)==s.Config.TLB/s.Config.Sets { entries=entries[:len(entries)-1] }
    s.TLB[k]=append([]*Page{page},entries...)
    page.R=1
    if op=="W" { page.M=1 }
    page.Last=s.Time
    page.Uses++
    page.Seen=true
    p.History=append(p.History,n)
    s.FaultHistory=append(s.FaultHistory,fault)
    line:=fmt.Sprintf("t=%d P%d %s %s page=%d frame=%d phys=%s %s",s.Time,pid,op,hex(addr),n,page.Frame,hex(page.Frame*s.Config.Page+offset),result)
    if switched { line+=" switch" }
    lines:=[]string{line}
    if s.Config.Tick>0&&s.Time%s.Config.Tick==0 {
        for _,pg:=range s.Frames { if pg!=nil { pg.Age=pg.Age/2+128*pg.R; pg.R=0 } }
        lines=append(lines,fmt.Sprintf("t=%d tick",s.Time))
    }
    return lines
}
func (s *Simulation) exit(pid int)(int,int) {
    freed,slots:=0,0
    for f,p:=range s.Frames { if p!=nil&&p.PID==pid { s.Frames[f]=nil; p.Frame=-1; s.removeTLB(p); freed++ } }
    for i,p:=range s.Slots { if p!=nil&&p.PID==pid { s.Slots[i]=nil; p.Slot=-1; slots++ } }
    p:=s.Processes[pid]
    p.Resident=0
    p.Exited=true
    return freed,slots
}
func (s *Simulation) clean() int {
    n:=0
    for _,p:=range s.Frames { if p!=nil&&p.M==1 { s.writeback(p); n++ } }
    return n
}
func (s *Simulation) lock(pid, first,last int, locked bool) {
    for _,p:=range s.Processes[pid].Pages[first:last+1] { p.Locked=locked }
}
func rerun(s *Simulation, events []Event, policy string, frames int) *Simulation {
    c:=s.Config
    c.Policy,c.Frames=policy,frames
    refs:=[][2]int{}
    for _,e:=range events { if e.Kind=="ACCESS" { refs=append(refs,[2]int{e.PID,e.Address/c.Page}) } }
    r:=newSimulation(c,refs)
    for _,id:=range s.pids() { r.declare(id,len(s.Processes[id].Pages)) }
    pos:=0
    for _,e:=range events {
        switch e.Kind {
        case "ACCESS": r.access(e.PID,e.Op,e.Address,pos); pos++
        case "EXIT": r.exit(e.PID)
        case "CLEAN": r.clean()
        case "LOCK": r.lock(e.PID,e.First,e.Last,e.Locked)
        }
    }
    return r
}
func command(s *Simulation, words []string, position int, trace *bool, events *[]Event) {
    c:=s.Config
    cmd,v:=words[0],words[1:]
    n:=func(i int)int{return number(v[i])}
    switch cmd {
    case "PROCESS":
        pid,count:=n(0),n(1)
        if position>0 { fail("processes are fixed") }
        if s.Processes[pid]!=nil { fail(fmt.Sprintf("duplicate process %d",pid)) }
        if count<1||count>256 { fail("invalid page count") }
        if len(s.Processes)>=8||(c.Scope=="LOCAL"&&len(s.Processes)>=c.Frames) { fail("too many processes") }
        s.declare(pid,count)
    case "EXIT":
        p:=s.process(n(0))
        f,sl:=s.exit(p.PID)
        *events=append(*events,Event{Kind:"EXIT",PID:p.PID})
        fmt.Printf("EXIT P%d freed=%d slots=%d\n",p.PID,f,sl)
    case "PROTECT","LOCK","UNLOCK":
        p:=s.process(n(0))
        first,last:=n(1),n(2)
        if first>last||last>=len(p.Pages) { fail("invalid page range") }
        if cmd=="PROTECT" { for _,pg:=range p.Pages[first:last+1] { pg.RO=v[3]=="RO" } } else {
            s.lock(p.PID,first,last,cmd=="LOCK")
            *events=append(*events,Event{Kind:"LOCK",PID:p.PID,First:first,Last:last,Locked:cmd=="LOCK"})
        }
    case "TRACE": *trace=v[0]=="ON"
    case "SUMMARY":
        fmt.Printf("SUMMARY policy=%s scope=%s time=%d\n",c.Policy,c.Scope,s.Time)
        seg,prot:=0,0
        for _,p:=range s.Processes { seg+=p.Seg; prot+=p.Prot }
        fmt.Printf("total faults=%d zero=%d swapin=%d faultrate=%s tlbhits=%d tlbrate=%s writebacks=%d switches=%d segfaults=%d protfaults=%d\n",s.Faults,s.Zeros,s.Swapins,ratio(s.Faults,s.Time),s.Hits,ratio(s.Hits,s.Time),s.Writes,s.Switches,seg,prot)
        for _,id:=range s.pids() {
            p:=s.Processes[id]
            fmt.Printf("P%d accesses=%d faults=%d writebacks=%d segfaults=%d protfaults=%d resident=%d peak=%d",id,len(p.History),p.Faults,p.Writes,p.Seg,p.Prot,p.Resident,p.Peak)
            if c.Scope=="LOCAL" { fmt.Printf(" quota=%d",s.quota(id)) }
            if p.Exited { fmt.Print(" exited") }
            fmt.Println()
        }
    case "FRAMES":
        used:=0
        for _,p:=range s.Frames { if p!=nil { used++ } }
        fmt.Printf("FRAMES used=%d/%d\n",used,c.Frames)
        for f,p:=range s.Frames {
            if p==nil { fmt.Printf("%d free\n",f); continue }
            fmt.Printf("%d %s R=%d M=%d load=%d last=%d uses=%d age=%d",f,label(p),p.R,p.M,p.Load,p.Last,p.Uses,p.Age)
            if p.Locked { fmt.Print(" locked") }
            fmt.Println()
        }
        if contains([]string{"CLOCK","ECLOCK","WSCLOCK"},c.Policy) {
            if c.Scope=="GLOBAL" { fmt.Printf("hand=%d\n",s.Hand) } else {
                fmt.Print("hand")
                for _,id:=range s.pids() { fmt.Printf(" P%d=%d",id,s.Processes[id].Hand) }
                fmt.Println()
            }
        }
    case "PAGETABLE":
        p:=s.process(n(0))
        fmt.Printf("PAGETABLE P%d pages=%d resident=%d\n",p.PID,len(p.Pages),p.Resident)
        for _,pg:=range p.Pages {
            if !pg.Seen { continue }
            if pg.Frame>=0 { fmt.Printf("%d frame=%d R=%d M=%d",pg.Number,pg.Frame,pg.R,pg.M) } else if pg.Slot>=0 { fmt.Printf("%d swap=%d",pg.Number,pg.Slot) } else { fmt.Printf("%d zero",pg.Number) }
            if pg.RO { fmt.Print(" RO") }
            if pg.Locked { fmt.Print(" locked") }
            fmt.Println()
        }
    case "TLB":
        used:=0
        for _,set:=range s.TLB { used+=len(set) }
        fmt.Printf("TLB used=%d/%d sets=%d\n",used,c.TLB,c.Sets)
        for i,set:=range s.TLB {
            fmt.Printf("set %d:",i)
            for _,p:=range set { fmt.Printf(" %s->%d",label(p),p.Frame) }
            fmt.Println()
        }
    case "SWAP":
        used:=0
        for _,p:=range s.Slots { if p!=nil { used++ } }
        fmt.Printf("SWAP used=%d\n",used)
        for i,p:=range s.Slots { if p!=nil { fmt.Printf("%d %s\n",i,label(p)) } }
    case "CLEAN":
        fmt.Printf("CLEAN written=%d\n",s.clean())
        *events=append(*events,Event{Kind:"CLEAN"})
    case "COMPARE":
        fmt.Printf("COMPARE accesses=%d frames=%d\n",s.Time,c.Frames)
        results:=make([]*Simulation,len(policies))
        order:=make([]int,len(policies))
        for i,p:=range policies {
            r:=rerun(s,*events,p,c.Frames)
            results[i],order[i]=r,i
            fmt.Printf("%s faults=%d writebacks=%d tlbhits=%d\n",p,r.Faults,r.Writes,r.Hits)
        }
        sort.SliceStable(order,func(i,j int)bool { a,b:=results[order[i]],results[order[j]]; return a.Faults<b.Faults||(a.Faults==b.Faults&&a.Writes<b.Writes) })
        fmt.Print("ranking")
        for _,i:=range order { fmt.Print(" ",policies[i]) }
        fmt.Println()
    case "CURVE":
        if !contains(policies,v[0]) { fail("unknown policy") }
        lo,hi:=n(1),n(2)
        if lo<1||lo>hi||hi>16||(c.Scope=="LOCAL"&&lo<len(s.Processes)) { fail("invalid frame range") }
        fmt.Printf("CURVE %s frames=%d..%d\n",v[0],lo,hi)
        previous:=-1
        for f:=lo; f<=hi; f++ {
            faults:=rerun(s,*events,v[0],f).Faults
            fmt.Printf("F=%d faults=%d",f,faults)
            if previous>=0&&faults>previous { fmt.Print(" ANOMALY") }
            fmt.Println()
            previous=faults
        }
    case "EAT":
        if s.Time==0 { fmt.Println("EAT accesses=0"); return }
        total:=int64(n(0))*int64(s.Time)+int64(n(1))*int64(2*s.Time-s.Hits)+int64(n(2))*int64(s.Swapins+s.Writes)
        average:=100*total/int64(s.Time)
        fmt.Printf("EAT accesses=%d total=%d average=%d.%02d\n",s.Time,total,average/100,average%100)
    case "TIMELINE":
        w:=n(0)
        if w<1 { fail("invalid window") }
        fmt.Printf("TIMELINE window=%d",w)
        for i:=0;i<len(s.FaultHistory);i+=w { total:=0; for j:=i;j<i+w&&j<len(s.FaultHistory);j++ { total+=s.FaultHistory[j] }; fmt.Print(" ",total) }
        fmt.Println()
    case "WSET","HOT":
        p:=s.process(n(0))
        k:=n(1)
        if k<1 { if cmd=="WSET" { fail("invalid window") }; fail("invalid count") }
        counts:=map[int]int{}
        history:=p.History
        if cmd=="WSET"&&len(history)>k { history=history[len(history)-k:] }
        for _,pg:=range history { counts[pg]++ }
        pages:=[]int{}
        for pg:=range counts { pages=append(pages,pg) }
        sort.Ints(pages)
        if cmd=="WSET" {
            fmt.Printf("WSET P%d window=%d size=%d",p.PID,k,len(pages))
            for _,pg:=range pages { fmt.Print(" ",pg) }
        } else {
            sort.SliceStable(pages,func(i,j int)bool{return counts[pages[i]]>counts[pages[j]]})
            fmt.Printf("HOT P%d",p.PID)
            for i,pg:=range pages { if i>=k { break }; fmt.Printf(" %d:%d",pg,counts[pg]) }
        }
        fmt.Println()
    }
}
func expand(lines []string) []Item {
    items:=[]Item{}
    add:=func(pid int,op string,addr int){items=append(items,Item{Kind:"ACCESS",PID:pid,Op:op,Address:addr})}
    for _,line:=range lines {
        w:=strings.Fields(line)
        switch w[0] {
        case "LOOP":
            for r:=0;r<number(w[6]);r++ { for i:=0;i<number(w[5]);i++ { add(number(w[1]),w[2],address(w[3])+i*number(w[4])) } }
        case "RAND":
            x:=int64(number(w[5]))
            lo,hi:=address(w[2]),address(w[3])
            for i:=0;i<number(w[4]);i++ {
                x=x*48271%2147483647
                addr:=lo+int(x%int64(hi-lo))
                x=x*48271%2147483647
                op:="R"
                if x%100<int64(number(w[6])) { op="W" }
                add(number(w[1]),op,addr)
            }
        default:
            if w[0][0]>='0'&&w[0][0]<='9' { add(number(w[0]),w[1],address(w[2])) } else { items=append(items,Item{Kind:w[0],Words:w}) }
        }
    }
    return items
}
func main() {
    reader:=bufio.NewReader(os.Stdin)
    readLine:=func() string {
        line,_:=reader.ReadString('\n')
        return strings.TrimSuffix(strings.TrimSuffix(line,"\n"),"\r")
    }
    n:=number(readLine())
    lines:=make([]string,n)
    for i:=range lines { lines[i]=readLine() }
    items:=expand(lines)
    var s *Simulation
    trace:=false
    position:=0
    events:=[]Event{}
    for index,item:=range items {
        func(){
            defer func(){if e:=recover();e!=nil { if msg,ok:=e.(string);ok { fmt.Println("ERROR",msg) } else { panic(e) } }}()
            if item.Kind=="SYSTEM" {
                s=nil
                c:=settings(item.Words[1:])
                refs:=[][2]int{}
                for _,future:=range items[index+1:] { if future.Kind=="SYSTEM" { break }; if future.Kind=="ACCESS" { refs=append(refs,[2]int{future.PID,future.Address/c.Page}) } }
                s=newSimulation(c,refs)
                trace,position,events=false,0,[]Event{}
                fmt.Printf("SYSTEM page=%d frames=%d tlb=%d sets=%d policy=%s scope=%s asid=%s tick=%d tau=%d seed=%d\n",c.Page,c.Frames,c.TLB,c.Sets,c.Policy,c.Scope,c.ASID,c.Tick,c.Tau,c.Seed)
                return
            }
            if s==nil { fail("no system") }
            if item.Kind=="ACCESS" {
                pos:=position
                position++
                p:=s.process(item.PID)
                if item.Address>=len(p.Pages)*s.Config.Page { p.Seg++; fmt.Printf("SEGFAULT P%d %s\n",item.PID,hex(item.Address)); return }
                if item.Op=="W"&&p.Pages[item.Address/s.Config.Page].RO { p.Prot++; fmt.Printf("PROTFAULT P%d %s\n",item.PID,hex(item.Address)); return }
                output:=s.access(item.PID,item.Op,item.Address,pos)
                events=append(events,Event{Kind:"ACCESS",PID:item.PID,Op:item.Op,Address:item.Address})
                if trace { for _,line:=range output { fmt.Println(line) } }
            } else { command(s,item.Words,position,&trace,&events) }
        }()
    }
}
