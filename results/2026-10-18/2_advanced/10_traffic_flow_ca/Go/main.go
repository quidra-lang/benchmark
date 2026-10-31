package main

import (
 "fmt"
 "os"
 "sort"
 "strconv"
 "strings"
)

type Rate struct { rate, end int }
type Source struct { node string; entry *Segment; rates []Rate; queue []*Vehicle; head, wait, maximum int; routes []Route }
type Ratio struct { n,d int64 }
func ratio(n,d int64) Ratio { g:=gcd(n,d); return Ratio{n/g,d/g} }
func (r Ratio) Mul(n,d int64) Ratio { a,b:=gcd(r.n,d),gcd(n,r.d); return ratio((r.n/a)*(n/b),(r.d/b)*(d/a)) }
func (r Ratio) Add(s Ratio) Ratio { g:=gcd(r.d,s.d); return ratio(r.n*(s.d/g)+s.n*(r.d/g),r.d*(s.d/g)) }
func (r Ratio) String() string { return frac(r.n,r.d) }
type Route struct { segments []*Segment; share Ratio; sink string }
type DetectorTotal struct { passing, occupancy, speed int64 }
type Detector struct { name string; segment *Segment; cell,width int; totals []DetectorTotal }
type Diagram struct { segment *Segment; lane,start,end int; lines []string }
type Ring struct { length,vmax,warm,measure int; seed int64; counts []int }
type Interval struct { arrived,inserted,exited,steps,speed int64 }
type Simulation struct {
 segments []*Segment; segmentByID map[string]*Segment; junctions []*Junction; incidents []*Incident; stops []*BusStop
 classes []*VehicleClass; sources []*Source; sinks []string
 detectors []*Detector; diagrams []*Diagram; tracks []int; tracked map[int]bool; rings []Ring
 random Minstd; steps,p,p0,interval,bin int; vehicles []*Vehicle; totals []Interval; events []string
}
func integer(s string) int { n,e:=strconv.Atoi(s); if e!=nil { panic(e) }; return n }
func readLines(path string) []string { b,e:=os.ReadFile(path); if e!=nil { panic(e) }; return strings.Split(strings.TrimSuffix(string(b),"\n"),"\n") }
func readSimulation() *Simulation {
 m:=&Simulation{segmentByID:map[string]*Segment{},tracked:map[int]bool{}}
 for _,line:=range readLines("input/network.txt") { p:=strings.Split(line," "); switch p[0] {
 case "SEGMENT":
  s:=&Segment{id:p[1],from:p[2],to:p[3],length:integer(p[4]),lanes:integer(p[5]),limit:integer(p[6])}; for l:=0;l<s.lanes;l++ { s.cells=append(s.cells,make([]int,s.length)) }; m.segments=append(m.segments,s); m.segmentByID[s.id]=s
 case "JUNCTION":
  j:=&Junction{node:p[1],offset:integer(p[2])}; for _,token:=range p[3:] { pair:=strings.Split(token,":"); ph:=Phase{duration:integer(pair[0]),token:pair[1],greens:map[string]bool{}}; if pair[1]!="-" { for _,id:=range strings.Split(pair[1],",") { ph.greens[id]=true } }; j.phases=append(j.phases,ph); j.cycle+=ph.duration }; m.junctions=append(m.junctions,j)
 case "INCIDENT": m.incidents=append(m.incidents,&Incident{segment:m.segmentByID[p[1]],lane:integer(p[2])-1,cell:integer(p[3]),start:integer(p[4]),end:integer(p[5])})
 case "STOP": stop:=&BusStop{segment:m.segmentByID[p[1]],cell:integer(p[2]),dwell:integer(p[3])}; stop.segment.stop=stop; m.stops=append(m.stops,stop)
 } }
 for _,s:=range m.segments { for _,j:=range m.junctions { if s.to==j.node { s.junction=j } } }
 for _,line:=range readLines("input/demand.txt") { p:=strings.Split(line," "); switch p[0] {
 case "CLASS": m.classes=append(m.classes,&VehicleClass{name:p[1],vmax:integer(p[2]),weight:integer(p[3]),overtake:p[4]=="Y",stops:p[5]=="Y"})
 case "SOURCE":
  source:=&Source{node:p[1]}; for _,s:=range m.segments { if s.from==source.node { source.entry=s } }; for _,token:=range p[2:] { pair:=strings.Split(token,":"); source.rates=append(source.rates,Rate{integer(pair[0]),integer(pair[1])}) }; m.sources=append(m.sources,source)
 case "SINK": m.sinks=append(m.sinks,p[1])
 case "TURN": from:=m.segmentByID[p[1]]; from.turns=append(from.turns,&Turn{target:m.segmentByID[p[2]],weight:integer(p[3])})
 } }
 for _,line:=range readLines("input/params.txt") { p:=strings.Split(line," "); switch p[0] {
 case "seed": m.random.state=int64(integer(p[1]))
 case "steps": m.steps=integer(p[1])
 case "dawdle": m.p=integer(p[1]); m.p0=integer(p[2])
 case "interval": m.interval=integer(p[1])
 case "bin": m.bin=integer(p[1])
 case "detector": m.detectors=append(m.detectors,&Detector{name:p[1],segment:m.segmentByID[p[2]],cell:integer(p[3]),width:integer(p[4])})
 case "diagram": m.diagrams=append(m.diagrams,&Diagram{segment:m.segmentByID[p[1]],lane:integer(p[2])-1,start:integer(p[3]),end:integer(p[4])})
 case "track": for _,token:=range p[1:] { id:=integer(token); m.tracks=append(m.tracks,id); m.tracked[id]=true }
 case "ring": r:=Ring{length:integer(p[1]),vmax:integer(p[2]),warm:integer(p[3]),measure:integer(p[4]),seed:int64(integer(p[5]))}; for _,token:=range p[6:] { r.counts=append(r.counts,integer(token)) }; m.rings=append(m.rings,r)
 } }
 m.totals=make([]Interval,m.steps/m.interval); for _,d:=range m.detectors { d.totals=make([]DetectorTotal,len(m.totals)) }; for _,s:=range m.sources { s.routes=enumerate(s.entry) }; return m
}
func enumerate(s *Segment) []Route {
 if s.junction==nil { return []Route{{[]*Segment{s},Ratio{1,1},s.to}} }; total:=0; for _,turn:=range s.turns { total+=turn.weight }; routes:=[]Route{}
 for _,turn:=range s.turns { for _,r:=range enumerate(turn.target) { path:=append([]*Segment{s},r.segments...); routes=append(routes,Route{path,r.share.Mul(int64(turn.weight),int64(total)),r.sink}) } }; return routes
}
func (m *Simulation) Enter(v *Vehicle,s *Segment) {
 v.route=append(v.route,s); s.entered++; v.turn=nil
 if s.junction!=nil { weights:=make([]int,len(s.turns)); for i,t:=range s.turns { weights[i]=t.weight }; v.turn=s.turns[selectWeight(weights,m.random.Draw())] }
}
func desiredLane(v *Vehicle) (int,int) {
 s,l,x:=v.segment,v.lane,v.cell; maximum:=v.Maximum(); here:=s.Free(l,x,maximum+1); want:=min(v.speed+1,maximum)
 if here<maximum+1 && x+here+1<s.length && s.cells[l][x+here+1]<0 { for _,next:=range []int{l+1,l-1} { if next>=0 && next<s.lanes && s.Free(next,x,maximum+1)>here && s.Safe(next,x) { return next,2 } } }
 if v.Heading() { if l>=1 && s.Safe(l-1,x) { return l-1,1 }; return l,-1 }
 if v.class.overtake && l+1<s.lanes && here<want && s.Free(l+1,x,maximum+1)>here && s.Safe(l+1,x) { return l+1,0 }
 if l>=1 && s.Free(l-1,x,maximum+1)>want && s.Safe(l-1,x) { return l-1,1 }; return l,-1
}
type LaneChange struct { vehicle *Vehicle; lane,kind int }
type Move struct { vehicle *Vehicle; segment *Segment; cell,u int }
func (m *Simulation) Run() {
 weights:=make([]int,len(m.classes)); for i,c:=range m.classes { weights[i]=c.weight }
 for t:=1;t<=m.steps;t++ {
  for _,i:=range m.incidents { if line:=i.Update(t); line!="" { m.events=append(m.events,line) } }
  index:=(t-1)/m.interval; interval:=&m.totals[index]
  for _,source:=range m.sources { rate:=0; for _,r:=range source.rates { if t<=r.end { rate=r.rate; break } }; if m.random.Draw()%1000<int64(rate) { c:=m.classes[selectWeight(weights,m.random.Draw())]; v:=&Vehicle{number:len(m.vehicles)+1,class:c,source:source,arrival:t,completed:map[*Segment]bool{}}; m.vehicles=append(m.vehicles,v); source.queue=append(source.queue,v); interval.arrived++ } }
  for _,source:=range m.sources {
   s:=source.entry
   for source.head<len(source.queue) { lane,first:=-1,-1; for l:=0;l<s.lanes;l++ { if s.cells[l][0]==0 && s.First(l)>first { lane=l; first=s.First(l) } }; if lane<0 { break }; v:=source.queue[source.head]; source.head++; v.Place(s,lane,0); v.inserted=t; m.Enter(v,s); interval.inserted++ }
   waiting:=len(source.queue)-source.head; if waiting>0 && source.wait==0 { source.wait=t; source.maximum=0 }; if source.wait!=0 { source.maximum=max(source.maximum,waiting); if waiting==0 { m.events=append(m.events,fmt.Sprintf("%04d QUEUE %s from %d max %d",t,source.node,source.wait,source.maximum)); source.wait=0 } }
  }
  changes:=[]LaneChange{}
  for _,s:=range m.segments { if s.lanes<2 { continue }; reserved:=make([][]bool,s.lanes); for l:=range reserved { reserved[l]=make([]bool,s.length) }; for l:=0;l<s.lanes;l++ { for _,id:=range s.cells[l] { if id<=0 { continue }; v:=m.vehicles[id-1]; if v.dwell>0 { continue }; next,kind:=desiredLane(v); if next!=l && !reserved[next][v.cell] { reserved[next][v.cell]=true; changes=append(changes,LaneChange{v,next,kind}) } } } }
  for _,change:=range changes { v:=change.vehicle; s:=v.segment; v.Place(s,change.lane,v.cell); v.laneChanges++; s.changes[change.kind]++ }
  moves:=[]Move{}
  for _,s:=range m.segments { for l:=0;l<s.lanes;l++ { for x:=s.length-1;x>=0;x-- { id:=s.cells[l][x]; if id<=0 { continue }; v:=m.vehicles[id-1]; a:=min(v.speed+1,v.Maximum()); gap:=s.Free(l,x,a)
   if gap<a && x+gap==s.length-1 { if s.junction==nil { gap=a } else if s.junction.Green(s.id,t) { target:=v.turn.target; gap+=target.Free(min(l,target.lanes-1),-1,a-gap) } }
   if v.Heading() { gap=min(gap,s.stop.cell-x) }; u:=randomSlowdown(min(a,gap),v.speed,m.random.Draw(),m.p,m.p0); if v.dwell>0 { u=0; v.dwell-- }; moves=append(moves,Move{v,s,x,u})
  } } }
  for i:=range moves { move:=&moves[i]; v,s,x:=move.vehicle,move.segment,move.cell; if x+move.u<s.length { v.Place(s,v.lane,x+move.u) } else if s.junction==nil { v.Leave(); v.exited=t; v.sink=s.to; interval.exited++ } }
  for i:=range moves { move:=&moves[i]; v,s,x:=move.vehicle,move.segment,move.cell; if x+move.u<s.length || s.junction==nil { continue }; turn:=v.turn; target:=turn.target; lane:=min(v.lane,target.lanes-1); want:=x+move.u-s.length; pos:=min(want,target.First(lane)-1); if pos<want { s.blocked++ }
   if pos>=0 { v.Place(target,lane,pos); move.u=s.length-x+pos; s.passed++; turn.vehicles++; m.Enter(v,target) } else { v.Place(s,v.lane,s.length-1); move.u=s.length-1-x }
  }
  for _,move:=range moves { v,u:=move.vehicle,move.u; v.steps++; v.distance+=int64(u); if u==0 { v.stoppedSteps++; if v.speed>0 { v.stopCount++ } }; v.speed=u; interval.steps++; interval.speed+=int64(u)
   if v.Heading() && v.lane==0 && v.cell==v.segment.stop.cell { s:=v.segment; v.completed[s]=true; v.dwell=s.stop.dwell; s.stop.buses++; m.events=append(m.events,fmt.Sprintf("%04d BUS_STOP %d %s cell %d",t,v.number,s.id,v.cell)) }
   if m.tracked[v.number] { line:=fmt.Sprintf("%04d EXIT %d",t,v.speed); if v.segment!=nil { line=fmt.Sprintf("%04d %s %d %d %d",t,v.segment.id,v.lane+1,v.cell,v.speed) }; v.trajectory=append(v.trajectory,line) }
   for _,d:=range m.detectors { if move.segment==d.segment && move.cell<d.cell && (v.segment!=d.segment || v.cell>=d.cell) { d.totals[index].passing++ } }
  }
  for _,d:=range m.detectors { for _,row:=range d.segment.cells { for _,id:=range row[d.cell:d.cell+d.width] { if id>0 { d.totals[index].occupancy++; d.totals[index].speed+=int64(m.vehicles[id-1].speed) } } } }
  for _,s:=range m.segments { count,queued:=0,0; speed:=int64(0); for _,row:=range s.cells { for _,id:=range row { if id>0 { count++; v:=m.vehicles[id-1]; speed+=int64(v.speed); if v.speed==0 { queued++ } } } }; s.vehicleSum+=int64(count); s.speedSum+=speed; s.maxVehicles=max(s.maxVehicles,count)
   if s.junction!=nil { green:=s.junction.Green(s.id,t); if green { s.greenCount++ }; s.queueSum+=int64(queued); s.maxQueue=max(s.maxQueue,queued); if t<m.steps && queued>0 && green && !s.junction.Green(s.id,t+1) { s.failures++ } }
  }
  for _,d:=range m.diagrams { if d.start<=t && t<=d.end { signal:="E"; if d.segment.junction!=nil { signal="R"; if d.segment.junction.Green(d.segment.id,t) { signal="G" } }; d.lines=append(d.lines,fmt.Sprintf("%04d %s %s",t,d.segment.CellsText(d.lane,m.vehicles),signal)) } }
 }
 for _,s:=range m.sources { if s.wait!=0 { m.events=append(m.events,fmt.Sprintf("%04d QUEUE %s from %d max %d open",m.steps,s.node,s.wait,s.maximum)) } }
}
func routeText(path []*Segment,separator string) string { ids:=make([]string,len(path)); for i,s:=range path { ids[i]=s.id }; return strings.Join(ids,separator) }
func equalRoute(a,b []*Segment) bool { if len(a)!=len(b) { return false }; for i:=range a { if a[i]!=b[i] { return false } }; return true }
func travelBlock(heading string,vehicles []*Vehicle,bin int) []string {
 times:=[]int64{}; total:=int64(0); for _,v:=range vehicles { if v.exited>0 { time:=v.Travel(); times=append(times,time); total+=time } }; if len(times)==0 { return []string{heading+" exited 0"} }; sort.Slice(times,func(i,j int)bool{return times[i]<times[j]}); line:=fmt.Sprintf("%s exited %d min %d p50 %d p90 %d max %d mean %s",heading,len(times),times[0],percentile(times,50),percentile(times,90),times[len(times)-1],dec(total,int64(len(times)),2)); return append([]string{line},histogram(times,bin)...)
}
func classBlock(heading string,vehicles []*Vehicle) []string {
 var inserted,exited,steps,distance,travel,delay,stopped,stops,changes int64
 for _,v:=range vehicles { if v.inserted>0 { inserted++ }; steps+=v.steps; distance+=v.distance; if v.exited>0 { exited++; travel+=v.Travel(); delay+=int64(v.inserted-v.arrival); stopped+=v.stoppedSteps; stops+=v.stopCount; changes+=v.laneChanges } }
 return []string{heading,fmt.Sprintf("  generated %d inserted %d exited %d in_network %d queued %d",len(vehicles),inserted,exited,inserted-exited,int64(len(vehicles))-inserted),fmt.Sprintf("  vehicle_steps %d distance %d mean_speed %s = %s",steps,distance,frac(distance,steps),dec(distance,steps,3)),fmt.Sprintf("  travel %s entry_delay %s stopped %s stops %s lane_changes %s",dec(travel,exited,2),dec(delay,exited,2),dec(stopped,exited,2),dec(stops,exited,2),dec(changes,exited,2))}
}
func (m *Simulation) Output() {
 files:=map[string][]string{"spacetime.txt":{},"detectors.csv":{"detector,interval,flow,density,speed"},"travel_times.txt":{},"class_stats.txt":{},"network_stats.txt":{},"timeline.csv":{"interval,arrived,inserted,exited,in_network,queued,mean_speed"},"tracks.txt":{},"fundamental.csv":{"ring,vehicles,density,flow,speed"},"events.txt":m.events}
 for _,d:=range m.diagrams { files["spacetime.txt"]=append(files["spacetime.txt"],fmt.Sprintf("DIAGRAM %s lane %d steps %d-%d",d.segment.id,d.lane+1,d.start,d.end)); files["spacetime.txt"]=append(files["spacetime.txt"],d.lines...) }
 for _,d:=range m.detectors { for k,total:=range d.totals { files["detectors.csv"]=append(files["detectors.csv"],fmt.Sprintf("%s,%d,%d,%s,%s",d.name,k+1,total.passing,dec(total.occupancy,int64(m.interval*d.width*d.segment.lanes),4),dec(total.speed,total.occupancy,2))) } }
 for _,c:=range m.classes { vehicles:=[]*Vehicle{}; for _,v:=range m.vehicles { if v.class==c { vehicles=append(vehicles,v) } }; heading:="CLASS "+c.name; files["travel_times.txt"]=append(files["travel_times.txt"],travelBlock(heading,vehicles,m.bin)...); over,stop:="N","N"; if c.overtake { over="Y" }; if c.stops { stop="Y" }; files["class_stats.txt"]=append(files["class_stats.txt"],classBlock(fmt.Sprintf("%s vmax %d weight %d overtake %s stops %s",heading,c.vmax,c.weight,over,stop),vehicles)...) }
 files["travel_times.txt"]=append(files["travel_times.txt"],travelBlock("ALL",m.vehicles,m.bin)...); files["class_stats.txt"]=append(files["class_stats.txt"],classBlock("ALL",m.vehicles)...)
 for _,s:=range m.sources { exited:=[]*Vehicle{}; for _,v:=range m.vehicles { if v.source==s && v.exited>0 { exited=append(exited,v) } }; files["travel_times.txt"]=append(files["travel_times.txt"],fmt.Sprintf("SOURCE %s exited %d",s.node,len(exited)))
  for _,r:=range s.routes { count,total:=int64(0),int64(0); for _,v:=range exited { if equalRoute(v.route,r.segments) { count++; total+=v.Travel() } }; files["travel_times.txt"]=append(files["travel_times.txt"],fmt.Sprintf("  ROUTE %s expected %s vehicles %d share %s mean %s",routeText(r.segments,","),r.share.String(),count,frac(count,int64(len(exited))),dec(total,count,2))) }
  for _,sink:=range m.sinks { share:=Ratio{0,1}; found:=false; for _,r:=range s.routes { if r.sink==sink { share=share.Add(r.share); found=true } }; if !found { continue }; count,total:=int64(0),int64(0); for _,v:=range exited { if v.sink==sink { count++; total+=v.Travel() } }; files["travel_times.txt"]=append(files["travel_times.txt"],fmt.Sprintf("  SINK %s expected %s vehicles %d share %s mean %s",sink,share.String(),count,frac(count,int64(len(exited))),dec(total,count,2))) }
 }
 for _,s:=range m.segments { files["network_stats.txt"]=append(files["network_stats.txt"],fmt.Sprintf("SEGMENT %s %s %s length %d lanes %d limit %d entered %d mean_vehicles %s density %s mean_speed %s max_vehicles %d changes %d/%d/%d",s.id,s.from,s.to,s.length,s.lanes,s.limit,s.entered,dec(s.vehicleSum,int64(m.steps),3),dec(s.vehicleSum,int64(m.steps*s.length*s.lanes),4),dec(s.speedSum,s.vehicleSum,2),s.maxVehicles,s.changes[0],s.changes[1],s.changes[2])) }
 for _,j:=range m.junctions { files["network_stats.txt"]=append(files["network_stats.txt"],j.Lines()...); for _,s:=range m.segments { if s.junction!=j { continue }; files["network_stats.txt"]=append(files["network_stats.txt"],fmt.Sprintf("  IN %s green %d passed %d blocked %d max_queue %d mean_queue %s failures %d",s.id,s.greenCount,s.passed,s.blocked,s.maxQueue,dec(s.queueSum,int64(m.steps),3),s.failures)); for _,turn:=range s.turns { files["network_stats.txt"]=append(files["network_stats.txt"],fmt.Sprintf("    TURN %s weight %d vehicles %d",turn.target.id,turn.weight,turn.vehicles)) } } }
 for _,s:=range m.stops { files["network_stats.txt"]=append(files["network_stats.txt"],fmt.Sprintf("STOP %s cell %d dwell %d buses %d",s.segment.id,s.cell,s.dwell,s.buses)) }
 for _,i:=range m.incidents { active:="none"; if i.activeStart>0 { active=fmt.Sprintf("%d-%d",i.activeStart,i.activeEnd) }; files["network_stats.txt"]=append(files["network_stats.txt"],fmt.Sprintf("INCIDENT %s lane %d cell %d planned %d-%d active %s",i.segment.id,i.lane+1,i.cell,i.start,i.end,active)) }
 onRoad,queued:=int64(0),int64(0); for k,total:=range m.totals { onRoad+=total.inserted-total.exited; queued+=total.arrived-total.inserted; files["timeline.csv"]=append(files["timeline.csv"],fmt.Sprintf("%d,%d,%d,%d,%d,%d,%s",k+1,total.arrived,total.inserted,total.exited,onRoad,queued,dec(total.speed,total.steps,2))) }
 for _,number:=range m.tracks { if number>len(m.vehicles) { files["tracks.txt"]=append(files["tracks.txt"],fmt.Sprintf("VEHICLE %d none",number)); continue }; v:=m.vehicles[number-1]; inserted,exited,sink:="-","-","-"; if v.inserted>0 { inserted=strconv.Itoa(v.inserted) }; if v.exited>0 { exited=strconv.Itoa(v.exited); sink=v.sink }; path:=routeText(v.route," "); if path=="" { path="-" }; files["tracks.txt"]=append(files["tracks.txt"],fmt.Sprintf("VEHICLE %d class %s source %s arrival %d inserted %s exited %s sink %s",number,v.class.name,v.source.node,v.arrival,inserted,exited,sink),"ROUTE "+path); files["tracks.txt"]=append(files["tracks.txt"],v.trajectory...) }
 for n,r:=range m.rings { for _,count:=range r.counts { total:=m.RingExperiment(r,count); files["fundamental.csv"]=append(files["fundamental.csv"],fmt.Sprintf("%d,%d,%s,%s,%s",n+1,count,dec(int64(count),int64(r.length),4),dec(total,int64(r.length*r.measure),4),dec(total,int64(count*r.measure),3))) } }
 if e:=os.MkdirAll("output",0755); e!=nil { panic(e) }; for name,lines:=range files { content:=""; if len(lines)>0 { content=strings.Join(lines,"\n")+"\n" }; if e:=os.WriteFile("output/"+name,[]byte(content),0644); e!=nil { panic(e) } }
}
func (m *Simulation) RingExperiment(r Ring,count int) int64 {
 type Car struct { position,speed int }; cars:=make([]Car,count); for i:=range cars { cars[i].position=i*r.length/count }; random:=Minstd{r.seed}; total:=int64(0); speeds:=make([]int,count)
 for t:=1;t<=r.warm+r.measure;t++ { sort.Slice(cars,func(i,j int)bool{return cars[i].position>cars[j].position}); for i,c:=range cars { ahead:=cars[(i+count-1)%count].position; gap:=(ahead-c.position-1+r.length)%r.length; speeds[i]=randomSlowdown(min(c.speed+1,r.vmax,gap),c.speed,random.Draw(),m.p,m.p0) }; for i:=range cars { cars[i].position=(cars[i].position+speeds[i])%r.length; cars[i].speed=speeds[i]; if t>r.warm { total+=int64(speeds[i]) } } }; return total
}
func main() { simulation:=readSimulation(); simulation.Run(); simulation.Output() }
