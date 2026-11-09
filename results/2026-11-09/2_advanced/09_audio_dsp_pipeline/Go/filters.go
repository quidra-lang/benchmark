package main

func fir(x []int64,divisor int64,taps []int64) ([]int64,int64) {y:=make([]int64,len(x));var clips int64;for n:=range y {var total int64;for k,h:=range taps {if n>=k {total+=h*x[n-k]}};y[n]=saturation(floorDiv(total,divisor),&clips)};return y,clips}
func biquad(x []int64,coefficients []int64) ([]int64,int64) {u:=x;var clips int64;for first:=0;first<len(coefficients);first+=5 {c:=coefficients[first:first+5];v:=make([]int64,len(x));for n:=range v {total:=c[0]*u[n];if n>=1 {total+=c[1]*u[n-1]};if n>=2 {total+=c[2]*u[n-2]};if n>=1 {total-=c[3]*v[n-1]};if n>=2 {total-=c[4]*v[n-2]};v[n]=saturation(floorDiv(total,16384),&clips)};u=v};return u,clips}
func movingAverage(x []int64,width int64) []int64 {y:=make([]int64,len(x));var total int64;for n,v:=range x {total+=v;if int64(n)>=width {total-=x[n-int(width)]};y[n]=rdiv(total,width)};return y}
func dcBlock(x []int64,num,den int64) ([]int64,int64) {y:=make([]int64,len(x));var clips,previousX,previousY int64;for n,v:=range x {y[n]=saturation(v-previousX+rdiv(num*previousY,den),&clips);previousX,previousY=v,y[n]};return y,clips}
