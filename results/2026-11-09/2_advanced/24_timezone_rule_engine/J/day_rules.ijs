MonthNames =: ;:'Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec'
WeekdayNames =: ;:'Sun Mon Tue Wed Thu Fri Sat'
CommonMonthDays =: 31 28 31 30 31 30 31 31 30 31 30 31
DaySeconds =: 86400
NegativeInfinity =: _4611686018427387904
PositiveInfinity =: 4611686018427387904
is_leap =: 3 : '((0=4|y)*.0~:100|y)+.0=400|y'
days_in_month =: 3 : 0
    'year month' =. y
    ((month-1){CommonMonthDays)+(month=2)*is_leap year
)
days_before_year =: 3 : 0
    previous =. y-1
    total =. (365*previous)+previous div 4
    total =. total-previous div 100
    total+previous div 400
)
day_number =: 3 : 0
    'year month day' =. y
    total =. (days_before_year year)-days_before_year 1970
    total =. total+day-1
    for_earlier. 1+i.month-1 do. total =. total+days_in_month year,earlier end.
    total
)
weekday_of =: 3 : '7|y+4'
date_of_day =: 3 : 0
    year =. 1970+y div 366
    while. (day_number year,1 1)>y do. year =. year-1 end.
    while. (day_number (year+1),1 1)<:y do. year =. year+1 end.
    month =. 1
    day =. 1+y-day_number year,1 1
    while. day>days_in_month year,month do.
        day =. day-days_in_month year,month
        month =. month+1
    end.
    year,month,day
)
time_value =: 3 : 0
    'year month day hour minute second' =. y
    (DaySeconds*day_number year,month,day)+(3600*hour)+(60*minute)+second
)
split_time =: 3 : 0
    seconds =. DaySeconds|y
    (date_of_day y div DaySeconds),(seconds div 3600),(60|seconds div 60),60|seconds
)
day_value =: 4 : 0
    'kind weekday day' =. x
    'year month' =. y
    if. kind=1 do.
        last =. day_number year,month,days_in_month year,month
        last-7|(weekday_of last)-weekday
    else.
        base =. day_number year,month,day
        if. kind=2 do. base+7|weekday-weekday_of base
        elseif. kind=3 do. base-7|(weekday_of base)-weekday
        else. base end.
    end.
)
