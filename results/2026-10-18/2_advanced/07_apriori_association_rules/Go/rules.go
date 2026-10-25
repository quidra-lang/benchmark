package main

type Fraction struct { N,D int64 }
func gcd(a,b int64) int64 {if a<0 {a=-a};for b!=0 {a,b=b,a%b};return a}
func fraction(n,d int64) Fraction {if d<0 {n,d=-n,-d};g:=gcd(n,d);return Fraction{n/g,d/g}}
func (a Fraction) compare(b Fraction) int {x,y:=a.N*b.D,b.N*a.D;if x<y {return -1};if x>y {return 1};return 0}
func (a Fraction) subtract(b Fraction) Fraction {return fraction(a.N*b.D-b.N*a.D,a.D*b.D)}
type Rule struct { Set,X,Y []int; Count int64; Support,Confidence,Lift,Leverage,Conviction,Improvement Fraction; Infinite bool; Rank int }
type RuleSet struct { Generated,Productive int; Rules []Rule }
func lift(total,together,first,second int64) Fraction {return fraction(total*together,first*second)}
func thresholds(confidence,lift Fraction,p Params) bool {return confidence.compare(p.Confidence)>=0&&lift.compare(p.Lift)>=0}
func ruleMetrics(set,x,y []int,count,total,nx,ny int64) Rule {r:=Rule{Set:set,X:x,Y:y,Count:count,Support:fraction(count,total),Confidence:fraction(count,nx),Lift:lift(total,count,nx,ny),Leverage:fraction(total*count-nx*ny,total*total),Infinite:nx==count};if !r.Infinite {r.Conviction=fraction((total-ny)*nx,total*(nx-count))};return r}
func compareRules(a,b Rule) int {if c:=a.Confidence.compare(b.Confidence);c!=0 {return -c};if c:=a.Lift.compare(b.Lift);c!=0 {return -c};if a.Count!=b.Count {if a.Count>b.Count {return -1};return 1};if c:=compareSets(a.X,b.X);c!=0 {return c};return compareSets(a.Y,b.Y)}
