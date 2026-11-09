coupon_schedule =: 3 : 0
    'issue maturity frequency eom longstub' =. y
    'year month day' =. civil_date maturity
    eom =. eom*.day=year month_length month
    step =. 12 div frequency
    dates =. 0$0
    boundary =. maturity
    while. boundary>issue do.
        dates =. dates,boundary
        index =. (12*year)+(month-1)-step*#dates
        nextyear =. index div 12
        nextmonth =. 1+12|index
        nextday =. nextyear month_length nextmonth
        if. -.eom do. nextday =. day<.nextday end.
        boundary =. day_number nextyear,nextmonth,nextday
    end.
    if. longstub*.(boundary~:issue)*.(#dates)>:2 do. dates =. }:dates end.
    issue,|.dates
)
