package main

func gain(x []int64,num,den int64) ([]int64,int64) {y:=make([]int64,len(x));var clips int64;for j,v:=range x {y[j]=saturation(rdiv(v*num,den),&clips)};return y,clips}
func mix(signals []*Signal,weights []int64,den int64) ([]int64,int64) {length:=0;for _,s:=range signals {length=max(length,len(s.Samples))};y:=make([]int64,length);var clips int64;for j:=range y {var total int64;for k,s:=range signals {if j<len(s.Samples) {total+=weights[k]*s.Samples[j]}};y[j]=saturation(rdiv(total,den),&clips)};return y,clips}
func delay(x []int64,count int64) []int64 {y:=make([]int64,len(x)+int(count));copy(y[int(count):],x);return y}
func echo(x []int64,lag,num,den,tail int64) ([]int64,int64) {y:=make([]int64,len(x)+int(tail));copy(y,x);var clips int64;for j:=int(lag);j<len(y);j++ {y[j]=saturation(y[j]+rdiv(num*y[j-int(lag)],den),&clips)};return y,clips}
func resample(x []int64,oldRate,newRate int64) []int64 {length:=(int64(len(x)-1)*newRate)/oldRate+1;y:=make([]int64,int(length));for j:=range y {position:=int64(j)*oldRate;p,q:=position/newRate,position%newRate;y[j]=x[int(p)];if q>0 {y[j]+=rdiv((x[int(p)+1]-x[int(p)])*q,newRate)}};return y}
func fade(x []int64,in,out int64) []int64 {y:=append([]int64(nil),x...);for j:=int64(0);j<in;j++ {y[int(j)]=rdiv(y[int(j)]*j,in)};for j:=int64(len(y))-out;j<int64(len(y));j++ {y[int(j)]=rdiv(y[int(j)]*(int64(len(y))-1-j),out)};return y}
