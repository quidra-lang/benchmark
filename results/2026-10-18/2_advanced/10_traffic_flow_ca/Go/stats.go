package main

import (
 "fmt"
 "strings"
)
func gcd(a,b int64) int64 { for b != 0 { a,b = b,a%b }; return a }
func dec(a,b int64,d int) string { if b == 0 { return "-" }; scale := int64(1); for i:=0;i<d;i++ { scale*=10 }; z := (2*a*scale+b)/(2*b); return fmt.Sprintf("%d.%0*d",z/scale,d,z%scale) }
func frac(a,b int64) string { if b == 0 { return "-" }; g := gcd(a,b); return fmt.Sprintf("%d/%d",a/g,b/g) }
func percentile(times []int64,q int) int64 { return times[(q*len(times)+99)/100-1] }
func histogram(times []int64,width int) []string {
 first,last := int(times[0])/width,int(times[len(times)-1])/width; counts := make([]int,last-first+1); largest:=0
 for _, t := range times { k:=int(t)/width-first; counts[k]++; largest=max(largest,counts[k]) }; lines:=[]string{}
 for i,c:=range counts { lo:=(first+i)*width; line:=fmt.Sprintf("  %d-%d %d",lo,lo+width-1,c); stars:=(80*c+largest)/(2*largest); if stars>0 { line+=" "+strings.Repeat("*",stars) }; lines=append(lines,line) }; return lines
}
