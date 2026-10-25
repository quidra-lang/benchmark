package main

type Flow struct { Day int; Amount float64 }
type ZeroCurve struct { Days []int; Rates []float64 }
func (curve ZeroCurve) zero(day int) float64 {
    if day<=curve.Days[0] { return curve.Rates[0] }
    last:=len(curve.Days)-1; if day>=curve.Days[last] { return curve.Rates[last] }
    i:=1; for curve.Days[i]<day { i++ }; if curve.Days[i]==day { return curve.Rates[i] }
    return curve.Rates[i-1]+(curve.Rates[i]-curve.Rates[i-1])*(float64(day-curve.Days[i-1])/float64(curve.Days[i]-curve.Days[i-1]))
}
func (curve ZeroCurve) discount(day int,spread float64) float64 {
    rate:=curve.zero(day)+spread; growth:=1.0
    for i:=0;i<day/365;i++ { growth*=1+rate }
    return 1/(growth*(1+rate*float64(day%365)/365))
}
func (curve ZeroCurve) presentValue(flows []Flow,spread float64) float64 { total:=0.0; for _,flow:=range flows { total+=flow.Amount*curve.discount(flow.Day,spread) }; return total }
func (curve ZeroCurve) forward(start,end int) float64 { return (curve.discount(start,0)/curve.discount(end,0)-1)*365/float64(end-start) }
func (curve ZeroCurve) shifted(deltas []float64) ZeroCurve { rates:=make([]float64,len(curve.Rates)); for i,rate:=range curve.Rates { rates[i]=rate+deltas[i] }; return ZeroCurve{curve.Days,rates} }
func (curve ZeroCurve) spread(flows []Flow,target float64) float64 { return bisection(func(spread float64)float64 { return curve.presentValue(flows,spread) },-0.5,0.5,target) }
func bootstrap(settlement int,pillars []Pillar) ZeroCurve {
    curve:=ZeroCurve{}
    for _,pillar:=range pillars {
        boundaries:=couponSchedule(settlement,pillar.Maturity,pillar.Frequency,false,false)
        var flows []Flow
        for i:=1;i<len(boundaries);i++ { n,m:=yearFraction("30/360",boundaries[i-1],boundaries[i]); amount:=float64(pillar.Coupon)*float64(n)/(10000*float64(m)); if i==len(boundaries)-1 { amount++ }; flows=append(flows,Flow{boundaries[i]-settlement,amount}) }
        curve.Days=append(curve.Days,pillar.Maturity-settlement); curve.Rates=append(curve.Rates,0)
        index:=len(curve.Rates)-1
        curve.Rates[index]=bisection(func(rate float64)float64 { curve.Rates[index]=rate; return curve.presentValue(flows,0) },0,1,1)
    }
    return curve
}
