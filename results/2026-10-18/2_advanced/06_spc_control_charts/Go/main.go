package main

import (
 "fmt"
 "math"
 "os"
 "sort"
 "strconv"
 "strings"
)

type Pass struct { Count int; Limits [2]Limits; Out []int }
type Estimate struct { Passes []Pass; Retained,Removed []int; Limits [2]Limits; Converged bool }
type Pattern struct { Count int; Signals []Signal }
type BandPoint struct { Value,Width float64 }
type Event struct { Start,End,Onset,Out,Total,Kind int; Counts [5]int; Detection [9]int; Shift,Spread float64 }
type AttributePass struct { Count int; Center Center; Out []int }
type Attribute struct { Passes []AttributePass; Retained,Removed []int; Converged bool; Points []LotPoint; Signals []Signal }
type Analysis struct {
 S Settings; Values []int; Lots []Lot; Groups []Subgroup; C Constants
 Estimates [3]Estimate; Patterns [6]Pattern; Proposals [3]Pass
 Signals []Signal; Events []Event; Attributes [4]Attribute
 Upper,Lower []float64; EWMA,MA []BandPoint
 Mu,Sigma,Reference,H,Sbar,EW,MW float64
}
func numbers(first,last int) []int {var r []int;for i:=first;i<=last;i++ {r=append(r,i)};return r}
func without(all,removed []int) []int {found:=map[int]bool{};for _,i:=range removed {found[i]=true};var r []int;for _,i:=range all {if !found[i] {r=append(r,i)}};return r}
func real(v float64) string {s:=strconv.FormatFloat(v,'f',4,64);if s=="-0.0000" {return "0.0000"};return s}
func list(v []int) string {if len(v)==0 {return "none"};s:=make([]string,len(v));for i,x:=range v {s[i]=strconv.Itoa(x)};return strings.Join(s," ")}
func ruleName(r int) string {if r==9 {return "UPPER"};if r==10 {return "LOWER"};return strconv.Itoa(r)}
func status(ok bool) string {if ok {return "converged"};return "stopped"}
func limitsText(label string,l Limits) string {return fmt.Sprintf("%s lcl %s cl %s ucl %s",label,real(l.LCL),real(l.CL),real(l.UCL))}
func pairText(f int,l [2]Limits) string {labels:=[3][2]string{{"XBAR","R"},{"XBAR","S"},{"I","MR"}};return limitsText(labels[f][0],l[0])+" "+limitsText(labels[f][1],l[1])}
func (a *Analysis) familyLimits(f int,ns []int) [2]Limits {return familyLimits(f,ns,a.Groups,a.Values,a.S.Size,a.C)}
func (a *Analysis) estimate(f int) {
 end:=a.S.Phase1;if f==2 {end*=a.S.Size};initial:=numbers(1,end);chosen:=initial;e:=Estimate{}
 for p:=1;p<=a.S.Passes;p++ {l:=a.familyLimits(f,chosen);series:=familySeries(f,chosen,a.Groups,a.Values);outs:=map[int]bool{}
  for j,seq:=range series {for k,v:=range seq.Values {if l[j].outside(v) {outs[seq.Numbers[k]]=true}}}
  var out []int;for _,i:=range chosen {if outs[i] {out=append(out,i)}};e.Passes=append(e.Passes,Pass{len(chosen),l,out});e.Limits=l
  if len(out)==0 {e.Converged=true;break};if p==a.S.Passes {break};chosen=without(chosen,out)
 }
 e.Retained=chosen;e.Removed=without(initial,chosen);a.Estimates[f]=e
 series:=familySeries(f,chosen,a.Groups,a.Values);for j,seq:=range series {chart:=2*f+j;a.Patterns[chart]=Pattern{len(seq.Values),checkRules(chart,seq,e.Limits[j],a.S.Rules[chart])}}
}
func (a *Analysis) signalGroup(s Signal) int {if s.Chart==4||s.Chart==5 {return (s.End-1)/a.S.Size+1};return s.End}
func (a *Analysis) eventOf(i int) int {for j,e:=range a.Events {if e.Start<=i&&i<=e.End {return j+1}};return 0}
func (a *Analysis) hasSignal(chart,end,rule int) bool {for _,s:=range a.Signals {if s.Chart==chart&&s.End==end&&(rule==0||s.Rule==rule) {return true}};return false}
func (a *Analysis) monitor() {
 s:=a.S;a.Mu=a.Estimates[0].Limits[0].CL;a.Sigma=a.Estimates[0].Limits[1].CL/a.C.D2/math.Sqrt(float64(s.Size));a.Reference=s.K*a.Sigma;a.H=s.H*a.Sigma;a.Sbar=a.Estimates[1].Limits[1].CL
 for chart:=0;chart<6;chart++ {seq:=Series{};end:=len(a.Groups);start:=s.Phase1+1;if chart>=4 {start=s.Phase1*s.Size+1;end=len(a.Values)}
  for i:=start;i<=end;i++ {v:=0.0;switch chart {case 0,2:v=a.Groups[i-1].Mean;case 1:v=float64(a.Groups[i-1].Range);case 3:v=a.Groups[i-1].SD;case 4:v=float64(a.Values[i-1]);case 5:v=float64(abs(a.Values[i-1]-a.Values[i-2]))};seq.Numbers=append(seq.Numbers,i);seq.Values=append(seq.Values,v)}
  a.Signals=append(a.Signals,checkRules(chart,seq,a.Estimates[chart/2].Limits[chart%2],s.Rules[chart])...)
 }
 size:=len(a.Groups)+1;a.Upper=make([]float64,size);a.Lower=make([]float64,size);a.EWMA=make([]BandPoint,size);a.MA=make([]BandPoint,size)
 upper,lower:=0.0,0.0;ur,lr:=0,0;z,factor:=a.Mu,1.0;q:=(1-s.Lambda)*(1-s.Lambda);rho:=s.Lambda/(2-s.Lambda);a.EW=s.E*a.Sigma*math.Sqrt(rho);a.MW=3*a.Sigma/math.Sqrt(float64(s.Span))
 for i:=s.Phase1+1;i<=len(a.Groups);i++ {mean:=a.Groups[i-1].Mean;upper=math.Max(0,upper+(mean-a.Mu-a.Reference));lower=math.Max(0,lower+(a.Mu-mean-a.Reference));if upper>0 {ur++} else {ur=0};if lower>0 {lr++} else {lr=0};a.Upper[i],a.Lower[i]=upper,lower
  if upper>a.H {a.Signals=append(a.Signals,Signal{6,9,i-ur+1,i,upper,"UP"});upper=0;ur=0};if lower>a.H {a.Signals=append(a.Signals,Signal{6,10,i-lr+1,i,lower,"DOWN"});lower=0;lr=0}
  z=s.Lambda*mean+(1-s.Lambda)*z;factor=factor*q;width:=s.E*a.Sigma*math.Sqrt(rho*(1-factor));a.EWMA[i]=BandPoint{z,width};a.bandSignal(7,i,i,a.EWMA[i])
  first:=max(s.Phase1+1,i-s.Span+1);var total int64;for j:=first;j<=i;j++ {total+=a.Groups[j-1].Total};a.MA[i]=BandPoint{float64(total)/float64(s.Size*(i-first+1)),3*a.Sigma/math.Sqrt(float64(i-first+1))};a.bandSignal(8,first,i,a.MA[i])
 }
 sort.Slice(a.Signals,func(i,j int) bool {x,y:=a.Signals[i],a.Signals[j];if x.Chart!=y.Chart {return x.Chart<y.Chart};if x.End!=y.End {return x.End<y.End};return x.Rule<y.Rule})
}
func (a *Analysis) bandSignal(chart,start,end int,p BandPoint) {if p.Value>a.Mu+p.Width {a.Signals=append(a.Signals,Signal{chart,9,start,end,p.Value,"UP"})} else if p.Value<a.Mu-p.Width {a.Signals=append(a.Signals,Signal{chart,10,start,end,p.Value,"DOWN"})}}
func (a *Analysis) buildEvents() {
 signalled:=map[int]bool{};for _,s:=range a.Signals {signalled[a.signalGroup(s)]=true}
 for i:=a.S.Phase1+1;i<=len(a.Groups);i++ {if !signalled[i] {continue};n:=len(a.Events);if n>0&&i-a.Events[n-1].End-1<=a.S.Gap {a.Events[n-1].End=i} else {a.Events=append(a.Events,Event{Start:i,End:i})}}
 for j:=range a.Events {e:=&a.Events[j];e.Onset=e.Start;cusum:=false
  for _,s:=range a.Signals {g:=a.signalGroup(s);if g<e.Start||g>e.End {continue};e.Total++;if e.Detection[s.Chart]==0||g<e.Detection[s.Chart] {e.Detection[s.Chart]=g};ix:=4;if s.Direction!="NONE" {ix=0;if s.Chart==1||s.Chart==3||s.Chart==5 {ix=2};if s.Direction=="DOWN" {ix++}};e.Counts[ix]++;if s.Chart==6&&(!cusum||s.Start<e.Onset) {e.Onset=s.Start;cusum=true}}
  for k:=1;k<5;k++ {if e.Counts[k]>e.Counts[e.Kind] {e.Kind=k}}
  var total int64;sd:=0.0;for i:=e.Start;i<=e.End;i++ {g:=a.Groups[i-1];total+=g.Total;sd+=g.SD;for _,v:=range g.Values {if v<a.S.LSL||v>a.S.USL {e.Out++}}};length:=e.End-e.Start+1;mean:=float64(total)/float64(a.S.Size*length);e.Shift=(mean-a.Mu)/a.Sigma;e.Spread=(sd/float64(length))/a.Sbar
 }
 for f:=0;f<3;f++ {ns:=append([]int(nil),a.Estimates[f].Retained...);for i:=a.S.Phase1+1;i<=len(a.Groups);i++ {if a.eventOf(i)!=0 {continue};if f==2 {ns=append(ns,numbers((i-1)*a.S.Size+1,i*a.S.Size)...)} else {ns=append(ns,i)}};a.Proposals[f]=Pass{Count:len(ns),Limits:a.familyLimits(f,ns)}}
}
func (a *Analysis) estimateAttributes() {
 for chart:=0;chart<4;chart++ {r:=Attribute{};initial:=numbers(1,len(a.Lots));chosen:=initial;var center Center
  for p:=1;p<=a.S.Passes;p++ {center=attributeCenter(chart,chosen,a.Lots);var out []int;for _,i:=range chosen {if attributePoint(chart,a.Lots[i-1],center).Status!="ok" {out=append(out,i)}};r.Passes=append(r.Passes,AttributePass{len(chosen),center,out});if len(out)==0 {r.Converged=true;break};if p==a.S.Passes {break};chosen=without(chosen,out)}
  r.Retained=chosen;r.Removed=without(initial,chosen);seq:=Series{Numbers:initial};for _,l:=range a.Lots {p:=attributePoint(chart,l,center);r.Points=append(r.Points,p);seq.Values=append(seq.Values,p.Z)};r.Signals=checkRules(chart,seq,Limits{-3,0,3},a.S.Rules[6]);a.Attributes[chart]=r
 }
}
func (a *Analysis) limitsLines() []string {
 lines:=[]string{fmt.Sprintf("characteristic %s",a.S.Name),fmt.Sprintf("subgroup_size %d",a.S.Size),fmt.Sprintf("subgroups %d",len(a.Groups)),fmt.Sprintf("samples %d",len(a.Values)),fmt.Sprintf("phase1_subgroups %d",a.S.Phase1)}
 for f,e:=range a.Estimates {lines=append(lines,"family "+familyNames[f]);for p,r:=range e.Passes {lines=append(lines,fmt.Sprintf("pass %d points %d %s out %s",p+1,r.Count,pairText(f,r.Limits),list(r.Out)))};lines=append(lines,fmt.Sprintf("result %s passes %d retained %d removed %s",status(e.Converged),len(e.Passes),len(e.Retained),list(e.Removed)))}
 for chart,p:=range a.Patterns {for _,s:=range p.Signals {lines=append(lines,fmt.Sprintf("phase1_signal %s %d %d %d %s",chartNames[chart],s.Rule,s.Start,s.End,real(s.Value)))};lines=append(lines,fmt.Sprintf("phase1_check %s points %d signals %d",chartNames[chart],p.Count,len(p.Signals)))}
 for f,p:=range a.Proposals {lines=append(lines,fmt.Sprintf("proposed %s points %d %s",familyNames[f],p.Count,pairText(f,p.Limits)))}
 target:="target "+real(a.Mu)+" sigma "+real(a.Sigma);lines=append(lines,"cusum "+target+" k "+real(a.Reference)+" h "+real(a.H),"ewma "+target+" lcl "+real(a.Mu-a.EW)+" ucl "+real(a.Mu+a.EW),fmt.Sprintf("ma %s span %d lcl %s ucl %s",target,a.S.Span,real(a.Mu-a.MW),real(a.Mu+a.MW)))
 for chart,name:=range chartNames {count:=0;ends:=map[int]bool{};counts:=map[int]int{};first:=0
  for _,s:=range a.Signals {if s.Chart==chart {count++;ends[s.End]=true;counts[s.Rule]++;if first==0||s.End<first {first=s.End}}};f:="none";if first>0 {f=strconv.Itoa(first)};points:=len(a.Groups)-a.S.Phase1;if chart==4||chart==5 {points*=a.S.Size};rules:=[]int{9,10};if chart<6 {rules=a.S.Rules[chart]};var by []string;for _,r:=range rules {by=append(by,fmt.Sprintf("%s:%d",ruleName(r),counts[r]))};lines=append(lines,fmt.Sprintf("phase2 %s points %d signals %d signalled %d first %s by_rule %s",name,points,count,len(ends),f,strings.Join(by," ")))
 }
 return lines
}
func (a *Analysis) signalLines() []string {lines:=[]string{"chart,rule,start,end,value,direction"};for _,s:=range a.Signals {lines=append(lines,fmt.Sprintf("%s,%s,%d,%d,%s,%s",chartNames[s.Chart],ruleName(s.Rule),s.Start,s.End,real(s.Value),s.Direction))};return lines}
func (a *Analysis) eventLines() []string {
 lines:=[]string{fmt.Sprintf("events %d",len(a.Events))};kinds:=[]string{"SHIFT_UP","SHIFT_DOWN","SPREAD_UP","SPREAD_DOWN","PATTERN"}
 for j,e:=range a.Events {var names,detection []string;for c,g:=range e.Detection {d:="-";if g>0 {names=append(names,chartNames[c]);d=strconv.Itoa(g)};detection=append(detection,chartNames[c]+":"+d)};lines=append(lines,fmt.Sprintf("event %d start %d end %d length %d signals %d charts %s location_up %d location_down %d spread_up %d spread_down %d pattern %d onset %d shift %s spread %s out_of_spec %d type %s",j+1,e.Start,e.End,e.End-e.Start+1,e.Total,strings.Join(names,","),e.Counts[0],e.Counts[1],e.Counts[2],e.Counts[3],e.Counts[4],e.Onset,real(e.Shift),real(e.Spread),e.Out,kinds[e.Kind]),fmt.Sprintf("detection %d %s",j+1,strings.Join(detection," ")))};return lines
}
func contains(ns []int,n int) bool {for _,v:=range ns {if v==n {return true}};return false}
func (a *Analysis) subgroupLines() []string {
 lines:=[]string{"subgroup,phase,mean,zone,range,sd,cusum_upper,cusum_lower,ewma,ma,signals,event"}
 for j,g:=range a.Groups {i:=j+1;phase:="phase1";monitored:="-,-,-,-";if i>a.S.Phase1 {phase="phase2";monitored=strings.Join([]string{real(a.Upper[i]),real(a.Lower[i]),real(a.EWMA[i].Value),real(a.MA[i].Value)},",")} else if contains(a.Estimates[0].Removed,i) {phase="excluded"};count:=0;for _,s:=range a.Signals {if a.signalGroup(s)==i {count++}};event:="-";if e:=a.eventOf(i);e>0 {event=strconv.Itoa(e)};lines=append(lines,fmt.Sprintf("%d,%s,%s,%s,%d,%s,%s,%d,%s",i,phase,real(g.Mean),zoneName(a.Estimates[0].Limits[0],g.Mean),g.Range,real(g.SD),monitored,count,event))};return lines
}
func (a *Analysis) attributeLines() []string {
 var lines []string
 for chart,r:=range a.Attributes {lines=append(lines,"chart "+attributeNames[chart]);for p,record:=range r.Passes {lines=append(lines,fmt.Sprintf("pass %d lots %d center %s out %s",p+1,record.Count,real(record.Center.Value),list(record.Out)))};lines=append(lines,fmt.Sprintf("result %s passes %d retained %d removed %s",status(r.Converged),len(r.Passes),len(r.Retained),list(r.Removed)))
  for j,p:=range r.Points {l:=a.Lots[j];v:=real(p.Value);if chart==1||chart==2 {v=strconv.Itoa(int(p.Value))};lines=append(lines,fmt.Sprintf("lot %d size %d value %s lcl %s ucl %s z %s status %s",l.Number,l.Inspected,v,real(p.LCL),real(p.UCL),real(p.Z),p.Status))};for _,s:=range r.Signals {lines=append(lines,fmt.Sprintf("signal %d %d %d %s",s.Rule,s.Start,s.End,real(s.Value)))};lines=append(lines,fmt.Sprintf("signals %d",len(r.Signals)))
 };return lines
}
func (a *Analysis) capabilityLines() []string {
 var lines []string
 for j,name:=range []string{"phase1","phase2"} {chosen:=a.Estimates[0].Retained;if j==1 {chosen=numbers(a.S.Phase1+1,len(a.Groups))};r:=capability(chosen,a.Groups,a.S,a.C);lines=append(lines,fmt.Sprintf("group %s subgroups %d values %d",name,len(chosen),r.Count))
  names:=[]string{"mean","sigma_within","sigma_sbar","sigma_overall","cp","cpu","cpl","cpk","pp","ppu","ppl","ppk","cpm"};values:=[]float64{r.Mean,r.Within,r.Sbar,r.Overall,r.CP,r.CPU,r.CPL,r.CPK,r.PP,r.PPU,r.PPL,r.PPK,r.CPM};for i,v:=range values {lines=append(lines,names[i]+" "+real(v))};lines=append(lines,"cpk_ci "+real(r.CPKCI[0])+" "+real(r.CPKCI[1]),"ppk_ci "+real(r.PPKCI[0])+" "+real(r.PPKCI[1]),fmt.Sprintf("below_lsl %d",r.Below),fmt.Sprintf("above_usl %d",r.Above),"ppm "+real(r.PPM))
  for _,i:=range chosen {for p,v:=range a.Groups[i-1].Values {side:="";if v<a.S.LSL {side="low"} else if v>a.S.USL {side="high"};if side!="" {lines=append(lines,fmt.Sprintf("out_of_spec sample %d subgroup %d value %d side %s",(i-1)*a.S.Size+p+1,i,v,side))}}};lines=append(lines,"verdict "+r.Verdict);lines=append(lines,histogram(r.Values,a.S)...)
 }
 for first:=a.S.Phase1+1;first+a.S.Window-1<=len(a.Groups);first+=a.S.Step {last:=first+a.S.Window-1;r:=capability(numbers(first,last),a.Groups,a.S,a.C);lines=append(lines,fmt.Sprintf("rolling %d %d mean %s sigma_within %s sigma_overall %s cpk %s ppk %s verdict %s",first,last,real(r.Mean),real(r.Within),real(r.Overall),real(r.CPK),real(r.PPK),r.Verdict))};return lines
}
func (a *Analysis) chartLines() []string {
 var lines []string
 for _,chart:=range []int{0,1,3} {f:=chart/2;l:=a.Estimates[f].Limits[chart%2];name:=chartNames[chart];if chart==0 {name="XBAR"};lines=append(lines,limitsText("chart "+name,l));for j,g:=range a.Groups {i:=j+1;mark:="1";if i>a.S.Phase1 {mark="2"} else if contains(a.Estimates[f].Removed,i) {mark="x"};v:=g.Mean;if chart==1 {v=float64(g.Range)} else if chart==3 {v=g.SD};lines=append(lines,fmt.Sprintf("%3d %s %s %s",i,mark,limitsBand(l,v,i>a.S.Phase1&&a.hasSignal(chart,i,0)),real(v)))}}
 lines=append(lines,"chart CUSUM h "+real(a.H));for i:=a.S.Phase1+1;i<=len(a.Groups);i++ {lines=append(lines,fmt.Sprintf("%3d %s %s %s",i,cusumBand(a.Upper[i],a.Lower[i],a.H,a.hasSignal(6,i,9),a.hasSignal(6,i,10)),real(a.Upper[i]),real(a.Lower[i])))}
 for _,chart:=range []int{7,8} {scale:=a.EW;points:=a.EWMA;if chart==8 {scale=a.MW;points=a.MA};lines=append(lines,limitsText("chart "+chartNames[chart],Limits{a.Mu-scale,a.Mu,a.Mu+scale}));for i:=a.S.Phase1+1;i<=len(a.Groups);i++ {p:=points[i];lines=append(lines,fmt.Sprintf("%3d %s %s %s %s",i,widthBand(scale,p.Width,p.Value,a.Mu,a.hasSignal(chart,i,0)),real(p.Value),real(a.Mu-p.Width),real(a.Mu+p.Width)))}}
 for c,r:=range a.Attributes {lines=append(lines,limitsText("chart "+[]string{"P_STD","NP_STD","C_STD","U_STD"}[c],Limits{-3,0,3}));for j,p:=range r.Points {lines=append(lines,fmt.Sprintf("%3d %s %s",a.Lots[j].Number,standardBand(p.Z,p.Status=="ok"),real(p.Z)))}};return lines
}
func main() {
 s,values,lots:=readDataset();a:=Analysis{S:s,Values:values,Lots:lots,Groups:subgroupStatistics(values,s.Size),C:constants[s.Size-2]};for f:=0;f<3;f++ {a.estimate(f)};a.monitor();a.buildEvents();a.estimateAttributes()
 if e:=os.MkdirAll("output",0755);e!=nil {panic(e)}
 reports:=[]struct{Name string;Lines []string}{{"limits.txt",a.limitsLines()},{"signals.csv",a.signalLines()},{"events.txt",a.eventLines()},{"subgroups.csv",a.subgroupLines()},{"attribute_charts.txt",a.attributeLines()},{"capability.txt",a.capabilityLines()},{"charts.txt",a.chartLines()}}
 for _,r:=range reports {if e:=os.WriteFile("output/"+r.Name,[]byte(strings.Join(r.Lines,"\n")+"\n"),0644);e!=nil {panic(e)}}
}
