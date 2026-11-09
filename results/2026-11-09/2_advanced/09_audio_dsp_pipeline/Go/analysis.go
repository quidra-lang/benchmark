package main

import "fmt"

func energy(x []int64) int64 {var total int64;for _,v:=range x {total+=v*v};return total}
func isqrt(n int64) int64 {low,high:=int64(0),n+1;for low+1<high {middle:=low+(high-low)/2;if middle<=n/middle {low=middle} else {high=middle}};return low}
func rms(x []int64) int64 {return isqrt(energy(x)/int64(len(x)))}
func zeroCrossings(x []int64) int64 {var count int64;for j:=1;j<len(x);j++ {if (x[j-1]<0)!=(x[j]<0) {count++}};return count}
func clipped(x []int64) int64 {var count int64;for _,v:=range x {if v==32767||v== -32768 {count++}};return count}
func crest(x []int64) string {e:=energy(x);if e==0 {return "none"};p:=peak(x);n,d:=p*p*int64(len(x)),e;a,b:=n,d;for b!=0 {a,b=b,a%b};return fmt.Sprintf("%d/%d",n/a,d/a)}
func pitchLag(x []int64,low,high int64) int64 {best:=low;var largest int64;for lag:=low;lag<=high;lag++ {var correlation int64;for n:=0;n+int(lag)<len(x);n++ {correlation+=x[n]*x[n+int(lag)]};if lag==low||correlation>largest {best,largest=lag,correlation}};if largest<=0 {return 0};return best}
func decimalTwo(h int64) string {return fmt.Sprintf("%d.%02d",h/100,h%100)}
func frequency(rate,lag int64) string {return decimalTwo(rdiv(100*rate,lag))}
