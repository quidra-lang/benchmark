package main

func couponSchedule(issue,maturity,frequency int,eom,long bool) []int {
    year,month,day:=civilDate(maturity)
    endRule:=eom && day==monthLength(year,month)
    var descending []int
    boundary:=maturity
    for boundary>issue {
        descending=append(descending,boundary)
        index:=year*12+month-1-(12/frequency)*len(descending)
        y,m:=index/12,index%12+1
        d:=min(day,monthLength(y,m)); if endRule { d=monthLength(y,m) }
        boundary=dayNumber(y,m,d)
    }
    if long && boundary!=issue && len(descending)>=2 { descending=descending[:len(descending)-1] }
    result:=[]int{issue}; for i:=len(descending)-1;i>=0;i-- { result=append(result,descending[i]) }
    return result
}
