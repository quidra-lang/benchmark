package main

import (
    "bufio"
    "container/heap"
    "fmt"
    "os"
    "regexp"
    "sort"
    "strconv"
    "strings"
)
var out=bufio.NewWriter(os.Stdout)
var types=[]string{"AND","OR","NAND","NOR","XOR","XNOR","NOT","BUF","MUX2","DFF"}
var counts=map[string]int{"BUILD":1,"RESET":0,"SET":3,"APPLY":2,"PULSE":3,"CLOCK":4,"RUN":1,"WATCH":1,"UNWATCH":1,"SHOW":0,"CHECK":2,"PROBE":1,"WAVE":2,"HISTORY":1,"ACTIVITY":1,"STATUS":0,"MODULES":0,"NETLIST":1,"HIERARCHY":1,"STATS":1,"TRUTHTABLE":1,"EQUIV":2,"FAULTS":1,"CRITICAL":1,"PERIOD":1}
var nameRE=regexp.MustCompile(`^[a-z][a-z0-9_]{0,15}$`)
var moduleRE=regexp.MustCompile(`^[A-Z][A-Z0-9_]{0,15}$`)
var numberRE=regexp.MustCompile(`^(0|[1-9][0-9]{0,8})$`)
func emit(s string){fmt.Fprintln(out,s)}
func fail(s string){panic(s)}
func has(a []string,s string)bool{for _,x:=range a{if x==s{return true}};return false}
func number(s string,positive bool)int{if !numberRE.MatchString(s){fail("bad number "+s)};n,_:=strconv.Atoi(s);if positive&&n==0{fail("bad number "+s)};return n}
func value(s string){if !has([]string{"0","1","X"},s){fail("bad value "+s)}}
func bits(r,n int)string{b:=make([]byte,n);for i:=range b{b[i]=byte('0'+((r>>(n-1-i))&1))};return string(b)}
func logic(k string,a []string)string{
    y:=a[0]
    switch k{
    case "AND","NAND":y="1";if has(a,"0"){y="0"}else if has(a,"X"){y="X"}
    case "OR","NOR":y="0";if has(a,"1"){y="1"}else if has(a,"X"){y="X"}
    case "XOR","XNOR":n:=0;for _,v:=range a{if v=="1"{n++}};y=strconv.Itoa(n%2);if has(a,"X"){y="X"}
    case "MUX2":if a[0]=="0"{y=a[1]}else if a[0]=="1"{y=a[2]}else if a[1]==a[2]{y=a[1]}else{y="X"}
    }
    if has([]string{"NAND","NOR","XNOR","NOT"},k){if y=="0"{return "1"};if y=="1"{return "0"}}
    return y
}
type Connection struct{port,signal string}
type Gate struct{name,kind string;inputs []string;output string;delay int}
type Item struct{gate *Gate;name string;module *Module;connections []Connection}
type Module struct{name string;inputs,outputs []string;body []Item}
type Circuit struct{name string;inputs,outputs,signals []string;gates []Gate;driver map[string]int;readers map[string][]int;flops,order []int;loop bool}
func circuit(m *Module)*Circuit{
    c:=&Circuit{name:m.name,inputs:m.inputs,outputs:m.outputs,driver:map[string]int{},readers:map[string][]int{}}
    var expand func(*Module,string,map[string]string)
    expand=func(m *Module,p string,ports map[string]string){
        actual:=func(s string)string{if x,ok:=ports[s];ok{return x};return p+s}
        for _,x:=range m.body{if x.gate!=nil{g:=*x.gate;g.name=p+g.name;g.inputs=make([]string,len(x.gate.inputs));for i,s:=range x.gate.inputs{g.inputs[i]=actual(s)};g.output=actual(g.output);c.gates=append(c.gates,g)}else{mapping:=map[string]string{};for _,v:=range x.connections{mapping[v.port]=actual(v.signal)};expand(x.module,p+x.name+".",mapping)}}
    }
    expand(m,"",map[string]string{});c.signals=append(c.signals,m.inputs...)
    for i,g:=range c.gates{c.signals=append(c.signals,g.output);c.driver[g.output]=i;if g.kind=="DFF"{c.flops=append(c.flops,i)};seen:=map[string]bool{};for _,s:=range g.inputs{if !seen[s]{c.readers[s]=append(c.readers[s],i);seen[s]=true}}}
    waiting:=make([]int,len(c.gates));ready:=[]int{};needed:=0
    for i,g:=range c.gates{if g.kind=="DFF"{continue};needed++;seen:=map[string]bool{};for _,s:=range g.inputs{if d,ok:=c.driver[s];ok&&c.gates[d].kind!="DFF"&&!seen[s]{waiting[i]++;seen[s]=true}};if waiting[i]==0{ready=append(ready,i)}}
    for len(ready)>0{i:=ready[len(ready)-1];ready=ready[:len(ready)-1];c.order=append(c.order,i);for _,r:=range c.readers[c.gates[i].output]{if c.gates[r].kind!="DFF"{waiting[r]--;if waiting[r]==0{ready=append(ready,r)}}}}
    c.loop=len(c.order)!=needed;return c
}
func(c *Circuit)combinational(){if len(c.flops)>0{fail(c.name+" is not combinational")};if c.loop{fail(c.name+" has a combinational loop")};if len(c.inputs)>8{fail(fmt.Sprintf("too many inputs %d",len(c.inputs)))}}
func(c *Circuit)evaluate(b,stuck,v string)string{values:=map[string]string{};for i,s:=range c.inputs{values[s]=b[i:i+1];if s==stuck{values[s]=v}};for _,i:=range c.order{g:=c.gates[i];a:=[]string{};for _,s:=range g.inputs{a=append(a,values[s])};values[g.output]=logic(g.kind,a);if g.output==stuck{values[g.output]=v}};a:=[]string{};for _,s:=range c.outputs{a=append(a,values[s])};return strings.Join(a,"")}
func(c *Circuit)arrivals(period bool)(map[string]int,map[string]int,map[string]string){
    late,early,prev:=map[string]int{},map[string]int{},map[string]string{}
    if period{for _,i:=range c.flops{g:=c.gates[i];late[g.output]=g.delay;early[g.output]=g.delay}}else{for _,s:=range c.inputs{late[s]=0;early[s]=0}}
    for _,i:=range c.order{g:=c.gates[i];best:="";minimum:=0;for _,s:=range g.inputs{if t,ok:=late[s];ok{if best==""{best=s;minimum=early[s]}else if t>late[best]{best=s};if early[s]<minimum{minimum=early[s]}}};if best!=""{late[g.output]=late[best]+g.delay;early[g.output]=minimum+g.delay;prev[g.output]=best}}
    return late,early,prev
}
type Event struct{time,sequence int;signal,value string}
type EventHeap []Event
func(h EventHeap)Len()int{return len(h)}
func(h EventHeap)Less(i,j int)bool{return h[i].time<h[j].time||h[i].time==h[j].time&&h[i].sequence<h[j].sequence}
func(h EventHeap)Swap(i,j int){h[i],h[j]=h[j],h[i]}
func(h *EventHeap)Push(x any){*h=append(*h,x.(Event))}
func(h *EventHeap)Pop()any{a:=*h;x:=a[len(a)-1];*h=a[:len(a)-1];return x}
type Change struct{time int;value string}
type Simulation struct{c *Circuit;values map[string]string;watch []string;time,sequence,processed int;queue EventHeap;history map[string][]Change;halted bool}
func(s *Simulation)reset(){s.values=map[string]string{};s.history=map[string][]Change{};for _,x:=range s.c.signals{s.values[x]="X";s.history[x]=nil};s.time=0;s.sequence=0;s.processed=0;s.queue=nil;s.halted=false}
func(s *Simulation)schedule(t int,x,v string){heap.Push(&s.queue,Event{t,s.sequence,x,v});s.sequence++}
func(s *Simulation)describe(a []string)[]string{b:=[]string{};for _,x:=range a{b=append(b,x+"="+s.values[x])};return b}
func(s *Simulation)run(end int){
    total,glitches:=0,0
    for len(s.queue)>0&&s.queue[0].time<end{
        t:=s.queue[0].time;original:=map[string]string{};count:=0
        for len(s.queue)>0&&s.queue[0].time==t{
            if count==1000{emit(fmt.Sprintf("halted: oscillation at time %d",t));s.queue=nil;s.time=t;s.halted=true;return}
            e:=heap.Pop(&s.queue).(Event);count++;s.processed++;old:=s.values[e.signal];if old==e.value{continue}
            if _,ok:=original[e.signal];!ok{original[e.signal]=old};s.values[e.signal]=e.value
            for _,i:=range s.c.readers[e.signal]{g:=s.c.gates[i];if g.kind!="DFF"{a:=[]string{};for _,x:=range g.inputs{a=append(a,s.values[x])};s.schedule(t+g.delay,g.output,logic(g.kind,a))}else if e.signal==g.inputs[0]&&old=="0"&&e.value=="1"{s.schedule(t+g.delay,g.output,s.values[g.inputs[1]])}}
        }
        total+=count;for x,v:=range original{if s.values[x]==v{glitches++}else{s.history[x]=append(s.history[x],Change{t,s.values[x]})}}
        for _,x:=range s.watch{if v,ok:=original[x];ok&&v!=s.values[x]{emit(fmt.Sprintf("%d %s %s",t,x,s.values[x]))}}
    }
    s.time=end;emit(fmt.Sprintf("run %d events %d glitches %d pending %d",end,total,glitches,len(s.queue)))
}
type Simulator struct{modules map[string]*Module;order []*Module;sim *Simulation}
func(s *Simulator)lookup(n string)*Module{m,ok:=s.modules[n];if !ok{fail("unknown module "+n)};return m}
func(s *Simulator)signal(x string){if _,ok:=s.sim.values[x];!ok{fail("unknown signal "+x)}}
func(s *Simulator)input(x string){if !has(s.sim.c.inputs,x){fail("not an input "+x)}}
func(s *Simulator)time(w string)int{t:=number(w,false);if t<s.sim.time{fail(fmt.Sprintf("time %d is in the past",t))};return t}
func(s *Simulator)define(header int,lines []string){
    line:=header;defer func(){if e:=recover();e!=nil{emit(fmt.Sprintf("error: line %d: %s",line,e))}}()
    w:=strings.Split(lines[0]," ");outCount,split:=0,0;for i:=3;i<len(w);i++{if w[i]=="OUT"{outCount++;split=i}}
    if len(w)<5||w[2]!="IN"||outCount!=1||w[len(w)-1]=="OUT"{fail("bad module header")}
    n:=w[1];if !moduleRE.MatchString(n){fail("bad module name "+n)};if _,ok:=s.modules[n];ok{fail("duplicate module "+n)}
    m:=&Module{name:n,inputs:w[3:split],outputs:w[split+1:]};seen:=map[string]bool{}
    ports:=append(append([]string{},m.inputs...),m.outputs...);for _,p:=range ports{if !nameRE.MatchString(p){fail("bad name "+p)};if seen[p]{fail("duplicate port "+p)};seen[p]=true}
    driven,used:=map[string]bool{},map[string]bool{};for _,p:=range m.inputs{driven[p]=true};type Read struct{line int;signal string};reads:=[]Read{};gates:=0
    for i,text:=range lines[1:]{line=header+i+1;a:=strings.Split(text," ");kind:=a[0]
        if has(types,kind){
            arrows:=0;for _,x:=range a{if x=="->"{arrows++}};if len(a)<5||a[len(a)-3]!="->"||arrows!=1{fail("bad gate syntax")}
            name:=a[1];if !nameRE.MatchString(name){fail("bad name "+name)};ins:=a[2:len(a)-3];output,delay:=a[len(a)-2],a[len(a)-1];lo,hi:=2,8
            if kind=="NOT"||kind=="BUF"{lo=1;hi=1}else if kind=="MUX2"{lo=3;hi=3}else if kind=="DFF"{hi=2}
            if len(ins)<lo||len(ins)>hi{fail(fmt.Sprintf("bad input count %d for %s",len(ins),kind))}
            for _,x:=range append(append([]string{},ins...),output){if !nameRE.MatchString(x){fail("bad name "+x)}}
            if !numberRE.MatchString(delay){fail("bad delay "+delay)};d,_:=strconv.Atoi(delay);if d>1000{fail("bad delay "+delay)}
            if used[name]{fail("duplicate name "+name)};if driven[output]{fail("multiple drivers for "+output)};used[name]=true;driven[output]=true
            m.body=append(m.body,Item{gate:&Gate{name,kind,ins,output,d}});gates++;for _,x:=range ins{reads=append(reads,Read{line,x})}
        }else if kind=="INST"{
            if len(a)<3{fail("bad instance syntax")};name:=a[1];if !nameRE.MatchString(name){fail("bad name "+name)};child:=s.lookup(a[2]);connections:=[]Connection{};seen:=map[string]bool{}
            for _,w:=range a[3:]{p:=strings.Split(w,"=");if len(p)!=2||p[0]==""||p[1]==""{fail("bad connection "+w)};port,x:=p[0],p[1];if !has(child.inputs,port)&&!has(child.outputs,port){fail("unknown port "+port)};if seen[port]{fail("duplicate connection "+port)};if !nameRE.MatchString(x){fail("bad name "+x)};seen[port]=true;connections=append(connections,Connection{port,x})}
            for _,p:=range child.inputs{if !seen[p]{fail("unconnected input "+p)}};if used[name]{fail("duplicate name "+name)}
            for _,v:=range connections{if has(child.outputs,v.port){if driven[v.signal]{fail("multiple drivers for "+v.signal)};driven[v.signal]=true}}
            used[name]=true;m.body=append(m.body,Item{name:name,module:child,connections:connections});for _,v:=range connections{if has(child.inputs,v.port){reads=append(reads,Read{line,v.signal})}}
        }else{fail("unknown statement "+kind)}
    }
    for _,x:=range m.outputs{reads=append(reads,Read{header,x})};for _,r:=range reads{if !driven[r.signal]{line=r.line;fail("undriven signal "+r.signal)}}
    s.modules[n]=m;s.order=append(s.order,m);emit(fmt.Sprintf("defined %s inputs %d outputs %d gates %d instances %d",n,len(m.inputs),len(m.outputs),gates,len(m.body)-gates))
}
func hierarchy(m *Module,depth int){for _,x:=range m.body{if x.gate==nil{emit(strings.Repeat("  ",depth)+x.name+" "+x.module.name);hierarchy(x.module,depth+1)}}}
func(s *Simulator)execute(line int,w []string){
    defer func(){if e:=recover();e!=nil{emit(fmt.Sprintf("error: line %d: %s",line,e))}}()
    cmd,a:=w[0],w[1:];n,ok:=counts[cmd];if !ok{fail("unknown command "+cmd)};if len(a)<n||(!has([]string{"WATCH","UNWATCH","SHOW"},cmd)&&len(a)!=n){fail("wrong argument count")}
    simulation:=strings.Fields("RESET SET APPLY PULSE CLOCK RUN WATCH UNWATCH SHOW CHECK PROBE WAVE HISTORY ACTIVITY STATUS")
    if has(simulation,cmd)&&s.sim==nil{fail("no circuit")};sim:=s.sim
    if has([]string{"SET","APPLY","PULSE","CLOCK","RUN"},cmd)&&sim.halted{fail("simulation halted")}
    if cmd=="MODULES"{emit(fmt.Sprintf("modules %d",len(s.order)));for _,m:=range s.order{emit(fmt.Sprintf("%s inputs %d outputs %d gates %d",m.name,len(m.inputs),len(m.outputs),len(circuit(m).gates)))};return}
    if has(strings.Fields("BUILD NETLIST HIERARCHY STATS TRUTHTABLE EQUIV FAULTS CRITICAL PERIOD"),cmd){
        m:=s.lookup(a[0]);var m2 *Module;if cmd=="EQUIV"{m2=s.lookup(a[1])};c:=circuit(m)
        switch cmd{
        case "BUILD":s.sim=&Simulation{c:c};s.sim.reset();emit(fmt.Sprintf("built %s signals %d gates %d",c.name,len(c.signals),len(c.gates)))
        case "NETLIST":emit(fmt.Sprintf("netlist %s gates %d signals %d",c.name,len(c.gates),len(c.signals)));for _,g:=range c.gates{emit(fmt.Sprintf("%s %s %s -> %s %d",g.name,g.kind,strings.Join(g.inputs," "),g.output,g.delay))}
        case "HIERARCHY":emit(m.name);hierarchy(m,1)
        case "STATS":
            levels:=map[string]int{};depth:=0;for _,i:=range c.order{g:=c.gates[i];v:=0;for _,x:=range g.inputs{if levels[x]>v{v=levels[x]}};levels[g.output]=v+1;if v+1>depth{depth=v+1}};d:=strconv.Itoa(depth);if c.loop{d="-"};emit(fmt.Sprintf("stats %s gates %d signals %d depth %s",c.name,len(c.gates),len(c.signals),d));words:=[]string{"types"};for _,k:=range types{n:=0;for _,g:=range c.gates{if g.kind==k{n++}};if n>0{words=append(words,k,strconv.Itoa(n))}};emit(strings.Join(words," "));best:=c.signals[0];for _,x:=range c.signals{if len(c.readers[x])>len(c.readers[best]){best=x}};emit(fmt.Sprintf("max fanout %s %d",best,len(c.readers[best])))
        case "CRITICAL","PERIOD":
            period:=cmd=="PERIOD";if period&&len(c.flops)==0{fail(c.name+" has no flip-flops")};if c.loop{fail(c.name+" has a combinational loop")};late,early,prev:=c.arrivals(period);ends:=c.outputs;heading:="critical";if period{ends=nil;for _,i:=range c.flops{ends=append(ends,c.gates[i].inputs[1])};heading=fmt.Sprintf("flip-flops %d period",len(c.flops))};best:=""
            for _,x:=range ends{t,ok:=late[x];if !period{if ok{emit(fmt.Sprintf("%s min %d max %d",x,early[x],t))}else{emit(x+" unreachable")}};if ok&&(best==""||t>late[best]){best=x}}
            if best==""{emit(heading+" none")}else{path:=[]string{best};for x:=prev[best];x!="";x=prev[x]{path=append(path,x)};for i,j:=0,len(path)-1;i<j;i,j=i+1,j-1{path[i],path[j]=path[j],path[i]};emit(fmt.Sprintf("%s %d: %s",heading,late[best],strings.Join(path," -> ")))}
        default:
            c.combinational();rows,expected:=[]string{},[]string{};for r:=0;r<1<<len(c.inputs);r++{b:=bits(r,len(c.inputs));rows=append(rows,b);expected=append(expected,c.evaluate(b,"",""))}
            if cmd=="TRUTHTABLE"{words:=append(append(append([]string{},c.inputs...),"|"),c.outputs...);emit(strings.Join(words," "));for r,b:=range rows{words:=[]string{};for _,x:=range b{words=append(words,string(x))};words=append(words,"|");for _,x:=range expected[r]{words=append(words,string(x))};emit(strings.Join(words," "))}}else if cmd=="EQUIV"{d:=circuit(m2);d.combinational();if len(c.inputs)!=len(d.inputs)||len(c.outputs)!=len(d.outputs){fail("port mismatch")};for r,b:=range rows{v:=d.evaluate(b,"","");if expected[r]!=v{emit(fmt.Sprintf("not equivalent at %s: %s vs %s",b,expected[r],v));return}};emit("equivalent")}else{undetected:=[]string{};tests:=map[int]bool{};for _,x:=range c.signals{for _,v:=range []string{"0","1"}{found:=-1;for r,b:=range rows{if c.evaluate(b,x,v)!=expected[r]{found=r;break}};if found<0{undetected=append(undetected,x+"/"+v)}else{tests[found]=true}}};emit(fmt.Sprintf("faults %d detected %d",2*len(c.signals),2*len(c.signals)-len(undetected)));for _,f:=range undetected{emit("undetected "+f)};words:=[]string{"tests"};for r,b:=range rows{if tests[r]{words=append(words,b)}};emit(strings.Join(words," "))}
        };return
    }
    switch cmd{
    case "RESET":sim.reset();emit("reset")
    case "SET":t:=s.time(a[0]);s.input(a[1]);value(a[2]);sim.schedule(t,a[1],a[2]);emit(fmt.Sprintf("set %s %s at %d",a[1],a[2],t))
    case "APPLY":t:=s.time(a[0]);b:=a[1];if len(b)!=len(sim.c.inputs)||strings.Trim(b,"01X")!=""{fail("bad vector "+b)};for i,x:=range sim.c.inputs{sim.schedule(t,x,b[i:i+1])};emit(fmt.Sprintf("apply %s at %d",b,t))
    case "PULSE","CLOCK":s.input(a[0]);t,width:=s.time(a[1]),number(a[2],true);if cmd=="PULSE"{sim.schedule(t,a[0],"1");sim.schedule(t+width,a[0],"0");emit(fmt.Sprintf("pulse %s %d %d",a[0],t,t+width))}else{count:=number(a[3],true);for i:=0;i<count;i++{sim.schedule(t+i*width,a[0],strconv.Itoa(i%2))};emit(fmt.Sprintf("clock %s events %d last %d",a[0],count,t+(count-1)*width))}
    case "RUN":t:=number(a[0],false);if t<=sim.time{fail(fmt.Sprintf("time %d is not after %d",t,sim.time))};sim.run(t)
    case "WATCH","UNWATCH":seen:=map[string]bool{};for _,x:=range a{s.signal(x);watched:=has(sim.watch,x);if cmd=="WATCH"&&(watched||seen[x]){fail("already watched "+x)};if cmd=="UNWATCH"&&(!watched||seen[x]){fail("not watched "+x)};seen[x]=true};if cmd=="WATCH"{sim.watch=append(sim.watch,a...)}else{remaining:=[]string{};for _,x:=range sim.watch{if !seen[x]{remaining=append(remaining,x)}};sim.watch=remaining};text:=strings.Join(sim.watch," ");if text==""{text="nothing"};emit("watching "+text)
    case "SHOW":for _,x:=range a{s.signal(x)};words:=sim.describe(a);if len(a)==0{words=append(append(sim.describe(sim.c.inputs),"|"),sim.describe(sim.c.outputs)...)};emit(strings.Join(words," "))
    case "CHECK":s.signal(a[0]);value(a[1]);text:="ok";if sim.values[a[0]]!=a[1]{text="failed ("+sim.values[a[0]]+")"};emit("check "+a[0]+"="+a[1]+" "+text)
    case "PROBE":x:=a[0];s.signal(x);text:="input";if i,ok:=sim.c.driver[x];ok{g:=sim.c.gates[i];text=fmt.Sprintf("%s %s %s delay %d",g.name,g.kind,strings.Join(sim.describe(g.inputs)," "),g.delay)};emit(x+"="+sim.values[x]+" driven by "+text);words:=[]string{"fanout",strconv.Itoa(len(sim.c.readers[x]))};for _,i:=range sim.c.readers[x]{words=append(words,sim.c.gates[i].name)};emit(strings.Join(words," "))
    case "WAVE":start,end:=number(a[0],false),number(a[1],false);if !(start<end&&end<=sim.time){fail(fmt.Sprintf("bad range %d %d",start,end))};if len(sim.watch)==0{fail("nothing watched")};for _,x:=range sim.watch{h:=sim.history[x];i:=0;v:="X";var wave strings.Builder;for t:=start;t<end;t++{for i<len(h)&&h[i].time<=t{v=h[i].value;i++};wave.WriteString(v)};emit(x+" "+wave.String())}
    case "HISTORY":x:=a[0];s.signal(x);h:=sim.history[x];words:=[]string{"history",x,"changes",strconv.Itoa(len(h))};for _,v:=range h{words=append(words,fmt.Sprintf("%d:%s",v.time,v.value))};emit(strings.Join(words," "))
    case "ACTIVITY":k:=number(a[0],true);ranked:=append([]string{},sim.c.signals...);sort.Slice(ranked,func(i,j int)bool{x,y:=ranked[i],ranked[j];return len(sim.history[x])>len(sim.history[y])||len(sim.history[x])==len(sim.history[y])&&x<y});if k>len(ranked){k=len(ranked)};for _,x:=range ranked[:k]{emit(fmt.Sprintf("%s %d",x,len(sim.history[x])))}
    case "STATUS":halted:="no";if sim.halted{halted="yes"};emit(fmt.Sprintf("circuit %s time %d pending %d events %d halted %s",sim.c.name,sim.time,len(sim.queue),sim.processed,halted));n:=map[string]int{};for _,v:=range sim.values{n[v]++};emit(fmt.Sprintf("values 0:%d 1:%d X:%d",n["0"],n["1"],n["X"]))
    }
}
func main(){defer out.Flush();scanner:=bufio.NewScanner(os.Stdin);lines:=[]string{};for scanner.Scan(){lines=append(lines,scanner.Text())};s:=Simulator{modules:map[string]*Module{}};for i:=0;i<len(lines)&&lines[i]!="END";i++{w:=strings.Split(lines[i]," ");if w[0]=="MODULE"{end:=i+1;for lines[end]!="ENDMODULE"{end++};s.define(i+1,lines[i:end]);i=end}else{s.execute(i+1,w)}}}
