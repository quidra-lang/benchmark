package main

func yearFraction(kind string,start,end int) (int64,int64) {
    if kind=="ACT/360" { return int64(end-start),360 }
    if kind=="ACT/365F" { return int64(end-start),365 }
    y1,m1,d1:=civilDate(start); y2,m2,d2:=civilDate(end)
    if kind=="ACT/ACT" {
        leap,other:=0,0
        for start<end { boundary:=min(dayNumber(y1+1,1,1),end); if leapYear(y1) { leap+=boundary-start } else { other+=boundary-start }; start=boundary; y1++ }
        return int64(365*leap+366*other),133590
    }
    if kind=="30/360" {
        february:=m1==2 && d1==monthLength(y1,m1)
        if february && m2==2 && d2==monthLength(y2,m2) { d2=30 }
        if february { d1=30 }
        if d2==31 && d1>=30 { d2=30 }
        if d1==31 { d1=30 }
    } else { d1=min(d1,30); d2=min(d2,30) }
    return int64(360*(y2-y1)+30*(m2-m1)+d2-d1),360
}
