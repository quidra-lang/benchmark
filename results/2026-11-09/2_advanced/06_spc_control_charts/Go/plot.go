package main

import "math"

func newBand() []byte {b:=make([]byte,61);for i:=range b {b[i]='.'};return b}
func place(b []byte,p int,c byte) {b[min(60,max(0,p))]=c}
func framedBand(center int) []byte {b:=newBand();place(b,0,':');place(b,60,':');place(b,center,'|');return b}
func symbol(signalled bool) byte {if signalled {return '*'};return 'o'}
func roundedPosition(v float64) int {r:=math.Floor(v+0.5);if r< -61 {return -61};if r>61 {return 61};return int(r)}
func limitsBand(l Limits,v float64,signalled bool) string {span:=l.UCL-l.LCL;b:=framedBand(roundedPosition(60*((l.CL-l.LCL)/span)));place(b,roundedPosition(60*((v-l.LCL)/span)),symbol(signalled));return string(b)}
func cusumBand(upper,lower,h float64,up,down bool) string {b:=framedBand(30);if lower>0 {c:=byte('-');if down {c='*'};place(b,30-min(30,roundedPosition(30*(lower/h))),c)};if upper>0 {c:=byte('+');if up {c='*'};place(b,30+min(30,roundedPosition(30*(upper/h))),c)};return string(b)}
func widthBand(scale,width,value,center float64,signalled bool) string {b:=newBand();e:=min(30,roundedPosition(30*(width/scale)));place(b,30,'|');place(b,30-e,':');place(b,30+e,':');d:=(value-center)/scale;place(b,30+roundedPosition(30*d),symbol(signalled));return string(b)}
func standardBand(z float64,ok bool) string {b:=framedBand(30);place(b,30+roundedPosition(10*z),symbol(!ok));return string(b)}
