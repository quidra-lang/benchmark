package main

func bisection(function func(float64)float64,low,high,target float64) float64 {
    for i:=0;i<80;i++ { middle:=(low+high)/2; if function(middle)>target { low=middle } else { high=middle } }
    return (low+high)/2
}
type YieldPricer struct { Flows []int64; W float64; Frequency int; Outstanding int64 }
type RiskMeasures struct { Macaulay,Modified,Convexity,DV01 float64 }
func (pricer YieldPricer) values(rate float64) []float64 {
    first:=1+pricer.W*rate/float64(pricer.Frequency); growth:=1+rate/float64(pricer.Frequency)
    factor:=1.0; values:=make([]float64,len(pricer.Flows))
    for i,flow:=range pricer.Flows { values[i]=float64(flow)/(first*factor); factor*=growth }
    return values
}
func (pricer YieldPricer) dirty(rate float64) float64 { total:=0.0; for _,value:=range pricer.values(rate) { total+=value }; return total*100/float64(pricer.Outstanding) }
func (pricer YieldPricer) solve(target float64) float64 { return bisection(pricer.dirty,0,1,target) }
func (pricer YieldPricer) risk(rate float64) RiskMeasures {
    total,weighted,curvature:=0.0,0.0,0.0
    for i,value:=range pricer.values(rate) { years:=(float64(i)+pricer.W)/float64(pricer.Frequency); total+=value; weighted+=years*value; curvature+=years*(years+1/float64(pricer.Frequency))*value }
    growth:=1+rate/float64(pricer.Frequency); macaulay:=weighted/total
    return RiskMeasures{macaulay,macaulay/growth,curvature/(total*growth*growth),(pricer.dirty(rate-0.0001)-pricer.dirty(rate+0.0001))/2}
}
