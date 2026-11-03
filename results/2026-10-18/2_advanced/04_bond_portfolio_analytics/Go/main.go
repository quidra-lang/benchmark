package main

import (
    "fmt"
    "os"
    "sort"
    "strconv"
    "strings"
)

var bondTypes=[]string{"FIXED","ZERO","AMORT","FRN"}
var bucketNames=[]string{"0-1Y","1-3Y","3-5Y","5-10Y","10Y+"}
var frequencies=map[int]bool{1:true,2:true,4:true,12:true}
var dayCounts=map[string]bool{"30/360":true,"30E/360":true,"ACT/360":true,"ACT/365F":true,"ACT/ACT":true}
var businessRules=map[string]bool{"FOLLOWING":true,"MODIFIED_FOLLOWING":true,"PRECEDING":true,"UNADJUSTED":true}
var optionKeys=map[string]map[string]bool{
    "FIXED":{"EOM":true,"LONG":true,"CALL":true}, "ZERO":{"EOM":true,"LONG":true},
    "AMORT":{"EOM":true,"LONG":true,"SINK":true}, "FRN":{"EOM":true,"LONG":true,"LAG":true,"CAP":true,"FLOOR":true},
}
type Row struct { Line int; Fields []string }
type RawScenario struct { Line int; Name string; Shifts []int }
type Params struct { Valuation,SettlementDays int; Scenarios []RawScenario; Limits [][]string }
type Fixing struct { Day int; Rate int64 }
type Pillar struct { Maturity int; Coupon int64; Frequency int }
type Scenario struct { Name string; Deltas []float64 }
type OptionValue struct { Date string; Amount int64 }
type DatedAmount struct { Day int; Amount int64 }
type Options struct { EOM,Long bool; Lag int; Cap,Floor int64; Sinks,Calls []OptionValue }
type Period struct { Number,Start,End,Payment int; N,M,Rate,Opening,Coupon,Principal,Cash int64 }
type Bond struct { Code,Kind string; Issue,Maturity int; Coupon int64; Frequency int; Daycount,BDC string; Face int64; Options Options; Schedule []int; Sinks map[int]int64; Calls []DatedAmount; Periods []*Period }
type Valuation struct {
    Bond *Bond
    Clean,Outstanding,AccruedAmount,CleanAmount,UnitValue int64
    Remaining,CashFlows []*Period
    Flows []Flow
    Pricer YieldPricer
    Accrued,Target,W,YTM,YTW,WAL,CurveClean,ZSpread float64
    Workout,NextPayment int
    Risk RiskMeasures
}
type Position struct { V *Valuation; Units,Book int64 }
type Exposure struct { Count int; Value int64; Duration,DV01 float64 }
type YearTotals struct { Coupon,Principal int64 }
type ScenarioResult struct { Name string; Values,PNLs []float64; Total,PNL float64 }

func integer(text string) int { value,err:=strconv.Atoi(text); if err!=nil { panic(err) }; return value }
func integer64(text string) int64 { value,err:=strconv.ParseInt(text,10,64); if err!=nil { panic(err) }; return value }
func readLines(name string) []string { data,err:=os.ReadFile("input/"+name); if err!=nil { panic(err) }; if len(data)==0 { return nil }; return strings.Split(strings.TrimSuffix(string(data),"\n"),"\n") }
func readRows(name string) []Row { var rows []Row; for index,line:=range readLines(name) { if index>0 { rows=append(rows,Row{index+1,strings.Split(line,",")}) } }; return rows }
func writeLines(name string,lines []string) { text:=""; if len(lines)>0 { text=strings.Join(lines,"\n")+"\n" }; if err:=os.WriteFile("output/"+name,[]byte(text),0644);err!=nil { panic(err) } }
func sortedKeys[T any](values map[string]T) []string { keys:=make([]string,0,len(values)); for key:=range values { keys=append(keys,key) }; sort.Strings(keys); return keys }
func contains(values []string,value string) bool { for _,item:=range values { if item==value { return true } }; return false }
func roundHalfUp(a,b int64) int64 { return (2*a+b)/(2*b) }
func hundredths(value int64) string { if value<0 { return "-"+hundredths(-value) }; return fmt.Sprintf("%d.%02d",value/100,value%100) }
func decimals(value float64,digits int) string {
    scale:=int64(1); for i:=0;i<digits;i++ { scale*=10 }
    negative:=value<0; if negative { value=-value }; rounded:=int64(value*float64(scale)+0.5)
    sign:=""; if negative && rounded>0 { sign="-" }
    return fmt.Sprintf("%s%d.%0*d",sign,rounded/scale,digits,rounded%scale)
}
func percent(value float64) string { return decimals(value*100,4) }
func amount(value float64) string { return decimals(value/100,2) }
func thousandths(text string) int64 { parts:=strings.Split(text,"."); return integer64(parts[0])*1000+integer64(parts[1]) }
func parseParams() Params {
    params:=Params{}
    for index,line:=range readLines("params.txt") { words:=strings.Split(line," "); switch words[0] {
    case "valuation_date": params.Valuation=parseDate(words[1])
    case "settlement_days": params.SettlementDays=integer(words[1])
    case "scenario": scenario:=RawScenario{Line:index+1,Name:words[1]}; for _,word:=range words[2:] { scenario.Shifts=append(scenario.Shifts,integer(word)) }; params.Scenarios=append(params.Scenarios,scenario)
    case "limit": params.Limits=append(params.Limits,words[1:])
    } }
    return params
}
func parseOptions(kind,text string) (Options,error) {
    options:=Options{Cap:1200}; seen:=map[string]bool{}
    if text!="-" { for _,item:=range strings.Split(text,";") {
        key,value,_:=strings.Cut(item,"=")
        if !optionKeys[kind][key] || seen[key] && key!="SINK" && key!="CALL" { return options,fmt.Errorf("invalid option") }; seen[key]=true
        switch key {
        case "EOM": options.EOM=true
        case "LONG": options.Long=true
        case "LAG": options.Lag=integer(value)
        case "CAP": options.Cap=integer64(value)
        case "FLOOR": options.Floor=integer64(value)
        case "SINK","CALL": date,number,_:=strings.Cut(value,":"); entry:=OptionValue{Date:date}; if key=="SINK" { entry.Amount=integer64(number); options.Sinks=append(options.Sinks,entry) } else { entry.Amount=thousandths(number); options.Calls=append(options.Calls,entry) }
        }
    } }
    if kind=="FRN" && (options.Lag<1 || options.Lag>5 || options.Cap>1200 || options.Floor>options.Cap) { return options,fmt.Errorf("invalid option") }
    return options,nil
}
func scheduleItems(items []OptionValue,boundaries []int,message string) ([]DatedAmount,error) {
    inner:=map[int]bool{}; for _,day:=range boundaries[1:len(boundaries)-1] { inner[day]=true }
    var result []DatedAmount
    for _,item:=range items { if !validDate(item.Date) { return nil,fmt.Errorf("%s",message) }; day:=parseDate(item.Date); if !inner[day] || len(result)>0 && day<=result[len(result)-1].Day { return nil,fmt.Errorf("%s",message) }; result=append(result,DatedAmount{day,item.Amount}) }
    return result,nil
}
func parseBond(fields []string,duplicate bool,calendar Calendar,fixings []Fixing) (*Bond,error) {
    failure:=func(message string)(*Bond,error) { return nil,fmt.Errorf("%s",message) }
    if duplicate { return failure("duplicate id") }
    if !contains(bondTypes,fields[1]) { return failure("unknown type") }
    if !validDate(fields[2]) || !validDate(fields[3]) { return failure("invalid date") }
    issue,maturity:=parseDate(fields[2]),parseDate(fields[3]); if maturity<=issue { return failure("maturity not after issue") }
    coupon,frequency,face:=integer64(fields[4]),integer(fields[5]),integer64(fields[8])
    if !frequencies[frequency] { return failure("invalid frequency") }
    if !dayCounts[fields[6]] { return failure("unknown day count") }
    if !businessRules[fields[7]] { return failure("unknown business day rule") }
    if face%100000!=0 || face>10000000 { return failure("invalid face") }
    if coupon>1200 || fields[1]=="ZERO" && coupon!=0 { return failure("invalid coupon") }
    options,err:=parseOptions(fields[1],fields[9]); if err!=nil { return nil,err }
    bond:=&Bond{Code:fields[0],Kind:fields[1],Issue:issue,Maturity:maturity,Coupon:coupon,Frequency:frequency,Daycount:fields[6],BDC:fields[7],Face:face,Options:options,Sinks:map[int]int64{}}
    bond.Schedule=couponSchedule(issue,maturity,frequency,options.EOM,options.Long)
    sinks,err:=scheduleItems(options.Sinks,bond.Schedule,"invalid sinking fund"); if err!=nil { return nil,err }; total:=int64(0)
    for _,sink:=range sinks { if sink.Amount==0 { return failure("invalid sinking fund") }; total+=sink.Amount; bond.Sinks[sink.Day]=sink.Amount }
    if bond.Kind=="AMORT" && (total==0 || total>=face) { return failure("invalid sinking fund") }
    bond.Calls,err=scheduleItems(options.Calls,bond.Schedule,"invalid call schedule"); if err!=nil { return nil,err }
    for _,call:=range bond.Calls { if call.Amount<100000 || call.Amount>110000 { return failure("invalid call schedule") } }
    opening:=face
    for i:=1;i<len(bond.Schedule);i++ {
        start,end:=bond.Schedule[i-1],bond.Schedule[i]; rate:=coupon
        if bond.Kind=="ZERO" { rate=0 } else if bond.Kind=="FRN" {
            reset:=calendar.move(calendar.adjust(start,bond.BDC),options.Lag,-1); found:=false
            for _,fixing:=range fixings { if fixing.Day>reset { break }; rate=fixing.Rate+coupon; found=true }
            if !found { return failure("missing fixing") }; rate=min(max(rate,options.Floor),options.Cap)
        }
        n,m:=yearFraction(bond.Daycount,start,end); principal:=bond.Sinks[end]; if i==len(bond.Schedule)-1 { principal=opening }; couponAmount:=roundHalfUp(opening*rate*n,10000*m)
        bond.Periods=append(bond.Periods,&Period{i,start,end,calendar.adjust(end,bond.BDC),n,m,rate,opening,couponAmount,principal,couponAmount+principal}); opening-=principal
    }
    return bond,nil
}
func newValuation(bond *Bond,clean int64,settlement int) *Valuation {
    index:=0; for bond.Periods[index].End<=settlement { index++ }; current:=bond.Periods[index]
    n,m:=yearFraction(bond.Daycount,current.Start,settlement)
    v:=&Valuation{Bond:bond,Clean:clean,Outstanding:current.Opening,Accrued:float64(current.Rate)*float64(n)/(100*float64(m)),Remaining:bond.Periods[index:],Workout:bond.Maturity}
    v.AccruedAmount=roundHalfUp(v.Outstanding*current.Rate*n,10000*m); v.CleanAmount=roundHalfUp(v.Outstanding*clean,100000); v.UnitValue=v.CleanAmount+v.AccruedAmount; v.Target=float64(clean)/1000+v.Accrued
    n,m=yearFraction(bond.Daycount,settlement,current.End); v.W=float64(bond.Frequency)*float64(n)/float64(m)
    var yieldFlows []int64
    for _,period:=range v.Remaining { yieldFlows=append(yieldFlows,period.Cash); if period.Cash>0 { v.CashFlows=append(v.CashFlows,period); v.Flows=append(v.Flows,Flow{period.Payment-settlement,float64(period.Cash)}) } }
    v.Pricer=YieldPricer{yieldFlows,v.W,bond.Frequency,v.Outstanding}; v.NextPayment=v.CashFlows[0].Payment
    return v
}
func (v *Valuation) analyze(curve ZeroCurve,settlement int) {
    v.YTM=v.Pricer.solve(v.Target); v.Risk=v.Pricer.risk(v.YTM); v.YTW=v.YTM
    for _,call:=range v.Bond.Calls { if call.Day>settlement {
        var flows []int64; for _,period:=range v.Remaining { flows=append(flows,period.Coupon); if period.End==call.Day { flows[len(flows)-1]+=roundHalfUp(period.Opening*call.Amount,100000); break } }
        rate:=(YieldPricer{flows,v.W,v.Bond.Frequency,v.Outstanding}).solve(v.Target); if rate<v.YTW { v.YTW=rate; v.Workout=call.Day }
    } }
    principalDays:=int64(0); for _,period:=range v.CashFlows { principalDays+=period.Principal*int64(period.Payment-settlement) }
    v.WAL=float64(principalDays)/float64(365*v.Outstanding); v.CurveClean=curve.presentValue(v.Flows,0)*100/float64(v.Outstanding)-v.Accrued
    v.ZSpread=curve.spread(v.Flows,float64(v.UnitValue))
}
func (p *Position) marketValue() int64 { return p.Units*p.V.UnitValue }
func (p *Position) face() int64 { return p.Units*p.V.Bond.Face }
func (p *Position) outstanding() int64 { return p.Units*p.V.Outstanding }
func (p *Position) gain() int64 { return p.Units*p.V.CleanAmount-p.Book }
func (p *Position) dv01() float64 { return p.V.Risk.DV01*float64(p.Units)*float64(p.V.Outstanding)/10000 }
func (p *Position) presentValue(curve ZeroCurve) float64 { return float64(p.Units)*curve.presentValue(p.V.Flows,p.V.ZSpread) }
func shiftVector(count,pillar int,shift float64) []float64 { deltas:=make([]float64,count); for i:=range deltas { if pillar<0 || pillar==i { deltas[i]=shift } }; return deltas }
func (e *Exposure) add(position *Position) { value:=position.marketValue(); e.Count++; e.Value+=value; e.Duration+=float64(value)*position.V.Risk.Modified; e.DV01+=position.dv01() }

func portfolioReports(name string,positions []*Position,curve ZeroCurve,scenarios []Scenario,limits [][]string,settlement int) ([]string,[]string,[]string) {
    var totalValue,totalFace,totalOutstanding,totalBook,totalGain,income int64
    ytm,modified,convexity,zspread,dv01:=0.0,0.0,0.0,0.0,0.0
    types:=map[string]*Exposure{}; for _,kind:=range bondTypes { types[kind]=&Exposure{} }; buckets:=make([]Exposure,5)
    ladder:=map[int]YearTotals{}; var cashFlows []Flow
    baseValues:=make([]float64,len(positions)); base:=0.0
    for i,position:=range positions {
        value:=position.marketValue(); v:=position.V
        totalValue+=value; totalFace+=position.face(); totalOutstanding+=position.outstanding(); totalBook+=position.Book; totalGain+=position.gain()
        ytm+=float64(value)*v.YTM; modified+=float64(value)*v.Risk.Modified; convexity+=float64(value)*v.Risk.Convexity; zspread+=float64(value)*v.ZSpread; dv01+=position.dv01()
        baseValues[i]=position.presentValue(curve); base+=baseValues[i]
        types[v.Bond.Kind].add(position); days:=v.Bond.Maturity-settlement; bucket:=4; for index,limit:=range []int{365,1095,1825,3650} { if days<limit { bucket=index; break } }; buckets[bucket].add(position)
        for j,period:=range v.CashFlows {
            if v.Flows[j].Day<=365 { income+=position.Units*period.Coupon }
            cashFlows=append(cashFlows,Flow{v.Flows[j].Day,float64(position.Units*period.Cash)})
            year,_,_:=civilDate(period.Payment); totals:=ladder[year]; totals.Coupon+=position.Units*period.Coupon; totals.Principal+=position.Units*period.Principal; ladder[year]=totals
        }
    }
    tv:=float64(totalValue); ytm/=tv; modified/=tv; convexity/=tv; zspread/=tv
    cashYield:=bisection(func(rate float64)float64 { return (ZeroCurve{[]int{0},[]float64{rate}}).presentValue(cashFlows,0) },0,1,tv)
    presentValue:=func(onCurve ZeroCurve)float64 { total:=0.0; for _,position:=range positions { total+=position.presentValue(onCurve) }; return total }
    duration:=func(pillar int)float64 { down:=presentValue(curve.shifted(shiftVector(len(curve.Rates),pillar,-0.0001))); up:=presentValue(curve.shifted(shiftVector(len(curve.Rates),pillar,0.0001))); return (down-up)/(2*0.0001*base) }
    report:=[]string{"portfolio "+name}
    for _,position:=range positions {
        v:=position.V; value:=position.marketValue()
        report=append(report,fmt.Sprintf("position %s face %s outstanding %s clean %s value %s weight %s book %s gain %s ytm %s modified %s dv01 %s",v.Bond.Code,hundredths(position.face()),hundredths(position.outstanding()),decimals(float64(v.Clean)/1000,6),hundredths(value),decimals(float64(value)*100/tv,4),hundredths(position.Book),hundredths(position.gain()),percent(v.YTM),decimals(v.Risk.Modified,4),decimals(position.dv01(),2)))
    }
    report=append(report,fmt.Sprintf("total positions %d face %s outstanding %s value %s book %s gain %s income %s",len(positions),hundredths(totalFace),hundredths(totalOutstanding),hundredths(totalValue),hundredths(totalBook),hundredths(totalGain),hundredths(income)))
    report=append(report,fmt.Sprintf("risk ytm %s yield %s modified %s convexity %s zspread %s dv01 %s",percent(ytm),percent(cashYield),decimals(modified,4),decimals(convexity,4),percent(zspread),decimals(dv01,2)))
    rates:=make([]string,len(curve.Rates)); for i:=range rates { rates[i]=decimals(duration(i),4) }
    report=append(report,fmt.Sprintf("curve effective %s krd %s",decimals(duration(-1),4),strings.Join(rates," ")))
    groupLine:=func(label,name string,group Exposure)string { return fmt.Sprintf("%s %s positions %d value %s weight %s duration %s dv01 %s",label,name,group.Count,hundredths(group.Value),decimals(float64(group.Value)*100/tv,4),decimals(group.Duration/tv,4),decimals(group.DV01,2)) }
    for _,kind:=range bondTypes { report=append(report,groupLine("type",kind,*types[kind])) }; for i,bucket:=range bucketNames { report=append(report,groupLine("bucket",bucket,buckets[i])) }
    var years []int; for year:=range ladder { years=append(years,year) }; sort.Ints(years); totalCoupon,totalPrincipal:=int64(0),int64(0)
    for _,year:=range years { totals:=ladder[year]; totalCoupon+=totals.Coupon; totalPrincipal+=totals.Principal; report=append(report,fmt.Sprintf("ladder %d coupon %s principal %s total %s",year,hundredths(totals.Coupon),hundredths(totals.Principal),hundredths(totals.Coupon+totals.Principal))) }
    report=append(report,fmt.Sprintf("ladder total coupon %s principal %s total %s",hundredths(totalCoupon),hundredths(totalPrincipal),hundredths(totalCoupon+totalPrincipal)))
    allScenarios:=append([]Scenario{{"BASE",shiftVector(len(curve.Rates),-1,0)}},scenarios...)
    var scenarioLines []string; var worst *ScenarioResult
    for index,scenario:=range allScenarios {
        shifted:=curve.shifted(scenario.Deltas); result:=&ScenarioResult{Name:scenario.Name,Values:make([]float64,len(positions)),PNLs:make([]float64,len(positions))}
        for i,position:=range positions { value:=position.presentValue(shifted); pnl:=value-baseValues[i]; result.Values[i]=value; result.PNLs[i]=pnl; result.Total+=value; scenarioLines=append(scenarioLines,strings.Join([]string{name,scenario.Name,position.V.Bond.Code,amount(value),amount(pnl)},",")) }
        result.PNL=result.Total-base; scenarioLines=append(scenarioLines,strings.Join([]string{name,scenario.Name,"*",amount(result.Total),amount(result.PNL)},","))
        if index>0 && (worst==nil || result.PNL<worst.PNL) { worst=result }
    }
    if worst!=nil {
        order:=make([]int,len(positions)); for i:=range order { order[i]=i }; sort.Slice(order,func(i,j int)bool { a,b:=order[i],order[j]; if worst.PNLs[a]!=worst.PNLs[b] { return worst.PNLs[a]<worst.PNLs[b] }; return positions[a].V.Bond.Code<positions[b].V.Bond.Code })
        stress:=fmt.Sprintf("stress worst %s pnl %s losers",worst.Name,amount(worst.PNL)); for _,index:=range order[:min(3,len(order))] { stress+=" "+positions[index].V.Bond.Code+" "+amount(worst.PNLs[index]) }; report=append(report,stress)
    }
    var compliance []string; breaches:=0
    for _,limit:=range limits {
        kind:=limit[0]; details:=""; breach:=false
        switch kind {
        case "position_weight": largest:=positions[0]; for _,position:=range positions { if position.marketValue()>largest.marketValue() { largest=position } }; value:=largest.marketValue(); upper:=integer64(limit[1]); details=fmt.Sprintf("%s %s limit %s",largest.V.Bond.Code,decimals(float64(value)*100/tv,4),hundredths(upper)); breach=value*10000>upper*totalValue
        case "type_weight": value:=types[limit[1]].Value; upper:=integer64(limit[2]); details=fmt.Sprintf("%s %s limit %s",limit[1],decimals(float64(value)*100/tv,4),hundredths(upper)); breach=value*10000>upper*totalValue
        case "max_maturity": years:=integer(limit[1]); count:=0; for _,position:=range positions { if position.V.Bond.Maturity-settlement>365*years { count++ } }; details=fmt.Sprintf("%dY positions %d",years,count); breach=count>0
        case "min_yield": lower:=integer64(limit[1]); details=percent(ytm)+" limit "+hundredths(lower); breach=ytm*10000<float64(lower)
        case "duration": low,high:=integer64(limit[1]),integer64(limit[2]); details=decimals(modified,4)+" range "+hundredths(low)+" "+hundredths(high); breach=modified<float64(low)/100 || modified>float64(high)/100
        case "dv01": upper:=integer64(limit[1]); details=decimals(dv01,2)+" limit "+hundredths(upper); breach=dv01*100>float64(upper)
        }
        result:="PASS"; if breach { result="BREACH"; breaches++ }; compliance=append(compliance,name+" "+kind+" "+details+" "+result)
    }
    compliance=append(compliance,fmt.Sprintf("%s breaches %d",name,breaches)); return report,scenarioLines,compliance
}
func main() {
    params:=parseParams(); calendar:=Calendar{}; for _,line:=range readLines("calendar.txt") { calendar[parseDate(line)]=true }
    var fixings []Fixing; for _,row:=range readRows("fixings.csv") { fixings=append(fixings,Fixing{parseDate(row.Fields[0]),integer64(row.Fields[1])}) }
    settlement:=calendar.move(params.Valuation,params.SettlementDays,1)
    var errors []string
    addError:=func(file string,line int,key,message string) { errors=append(errors,fmt.Sprintf("%s:%d: %s: %s",file,line,key,message)) }
    seen:=map[string]bool{}; var pillars []Pillar
    for _,row:=range readRows("curve_quotes.csv") {
        f:=row.Fields; reason:=""
        switch { case seen[f[0]]: reason="duplicate pillar"; case !validDate(f[0]): reason="invalid date"; case parseDate(f[0])<=settlement: reason="pillar not after settlement"; case !frequencies[integer(f[2])]: reason="invalid frequency" }
        if reason!="" { addError("curve_quotes.csv",row.Line,f[0],reason) } else { pillars=append(pillars,Pillar{parseDate(f[0]),integer64(f[1]),integer(f[2])}) }; seen[f[0]]=true
    }
    sort.Slice(pillars,func(i,j int)bool { return pillars[i].Maturity<pillars[j].Maturity })
    var scenarios []Scenario; seen=map[string]bool{}
    for _,scenario:=range params.Scenarios { if seen[scenario.Name] { addError("params.txt",scenario.Line,scenario.Name,"duplicate scenario") } else if len(scenario.Shifts)!=len(pillars) { addError("params.txt",scenario.Line,scenario.Name,"wrong number of shifts") } else { deltas:=make([]float64,len(scenario.Shifts)); for i,shift:=range scenario.Shifts { deltas[i]=float64(shift)*0.0001 }; scenarios=append(scenarios,Scenario{scenario.Name,deltas}) }; seen[scenario.Name]=true }
    bonds:=map[string]*Bond{}; seen=map[string]bool{}
    for _,row:=range readRows("bonds.csv") { bond,err:=parseBond(row.Fields,seen[row.Fields[0]],calendar,fixings); if err!=nil { addError("bonds.csv",row.Line,row.Fields[0],err.Error()) } else { bonds[bond.Code]=bond }; seen[row.Fields[0]]=true }
    valuations:=map[string]*Valuation{}; seen=map[string]bool{}
    for _,row:=range readRows("prices.csv") {
        code:=row.Fields[0]; bond:=bonds[code]; reason:=""; var v *Valuation
        switch { case bond==nil: reason="unknown bond"; case seen[code]: reason="duplicate price"; case !(bond.Issue<=settlement && settlement<bond.Maturity): reason="not outstanding"
        default: v=newValuation(bond,thousandths(row.Fields[1]),settlement); if !(v.Pricer.dirty(0)>v.Target && v.Target>v.Pricer.dirty(1)) { reason="yield out of range" }
        }
        if reason!="" { addError("prices.csv",row.Line,code,reason) } else { valuations[code]=v }; seen[code]=true
    }
    portfolios:=map[string]map[string]*Position{}
    for _,row:=range readRows("holdings.csv") {
        f:=row.Fields; code:=f[1]; face:=integer64(f[2]); reason:=""
        switch { case bonds[code]==nil: reason="unknown bond"; case valuations[code]==nil: reason="no price"; case face%bonds[code].Face!=0: reason="invalid face" }
        if reason!="" { addError("holdings.csv",row.Line,code,reason); continue }
        if portfolios[f[0]]==nil { portfolios[f[0]]=map[string]*Position{} }; if portfolios[f[0]][code]==nil { portfolios[f[0]][code]=&Position{V:valuations[code]} }
        position:=portfolios[f[0]][code]; units:=face/bonds[code].Face; position.Units+=units; position.Book+=roundHalfUp(units*position.V.Outstanding*thousandths(f[3]),100000)
    }
    curve:=bootstrap(settlement,pillars); for _,code:=range sortedKeys(valuations) { valuations[code].analyze(curve,settlement) }
    cashflows:=[]string{"bond,period,start,end,payment,fraction,rate_bp,outstanding,coupon,principal"}
    for _,code:=range sortedKeys(bonds) { for _,period:=range bonds[code].Periods { if period.Cash>0 { cashflows=append(cashflows,fmt.Sprintf("%s,%d,%s,%s,%s,%s,%d,%d,%d,%d",code,period.Number,formatDate(period.Start),formatDate(period.End),formatDate(period.Payment),decimals(float64(period.N)/float64(period.M),6),period.Rate,period.Opening,period.Coupon,period.Principal)) } } }
    analytics:=[]string{"bond,clean,accrued,dirty,ytm,ytw,workout,next_payment,wal,macaulay,modified,convexity,dv01,curve_clean,zspread"}
    for _,code:=range sortedKeys(valuations) { v:=valuations[code]; analytics=append(analytics,strings.Join([]string{code,decimals(float64(v.Clean)/1000,6),decimals(v.Accrued,6),decimals(v.Target,6),percent(v.YTM),percent(v.YTW),formatDate(v.Workout),formatDate(v.NextPayment),decimals(v.WAL,4),decimals(v.Risk.Macaulay,4),decimals(v.Risk.Modified,4),decimals(v.Risk.Convexity,4),decimals(v.Risk.DV01,6),decimals(v.CurveClean,6),percent(v.ZSpread)},",")) }
    curveLines:=[]string{"valuation "+formatDate(params.Valuation)+" settlement "+formatDate(settlement)}; previous:=0
    for i,pillar:=range pillars { day:=curve.Days[i]; curveLines=append(curveLines,fmt.Sprintf("pillar %s days %d frequency %d par %s zero %s df %s forward %s",formatDate(pillar.Maturity),day,pillar.Frequency,hundredths(pillar.Coupon),percent(curve.Rates[i]),decimals(curve.discount(day,0),6),percent(curve.forward(previous,day)))); previous=day }
    for year:=1;year<=curve.Days[len(curve.Days)-1]/365;year++ { day:=365*year; curveLines=append(curveLines,fmt.Sprintf("grid %dY days %d zero %s df %s forward %s",year,day,percent(curve.zero(day)),decimals(curve.discount(day,0),6),percent(curve.forward(day-365,day)))) }
    var report,compliance []string; scenarioLines:=[]string{"portfolio,scenario,bond,value,pnl"}
    for _,name:=range sortedKeys(portfolios) { var positions []*Position; for _,code:=range sortedKeys(portfolios[name]) { positions=append(positions,portfolios[name][code]) }; r,s,c:=portfolioReports(name,positions,curve,scenarios,params.Limits,settlement); report=append(report,r...); scenarioLines=append(scenarioLines,s...); compliance=append(compliance,c...) }
    if err:=os.MkdirAll("output",0755);err!=nil { panic(err) }
    writeLines("errors.txt",errors); writeLines("cashflows.csv",cashflows); writeLines("analytics.csv",analytics); writeLines("curve.txt",curveLines); writeLines("portfolio.txt",report); writeLines("scenarios.csv",scenarioLines); writeLines("compliance.txt",compliance)
}
