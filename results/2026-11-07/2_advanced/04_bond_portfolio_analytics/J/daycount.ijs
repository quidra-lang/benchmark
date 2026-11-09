DayCounts =: ' ' split '30/360 30E/360 ACT/360 ACT/365F ACT/ACT'
year_fraction =: 4 : 0
    'start finish' =. y
    if. x-:'ACT/360' do. (finish-start),360 return. end.
    if. x-:'ACT/365F' do. (finish-start),365 return. end.
    'year1 month1 day1' =. civil_date start
    'year2 month2 day2' =. civil_date finish
    if. x-:'ACT/ACT' do.
        numerator =. 0
        year =. year1
        while. start<finish do.
            boundary =. finish<.day_number (year+1),1 1
            multiplier =. 366-is_leap year
            numerator =. numerator+multiplier*boundary-start
            start =. boundary
            year =. year+1
        end.
        numerator,133590 return.
    end.
    if. x-:'30/360' do.
        firstfeb =. (month1=2)*.day1=year1 month_length 2
        lastfeb =. (month2=2)*.day2=year2 month_length 2
        if. firstfeb*.lastfeb do. day2 =. 30 end.
        if. firstfeb do. day1 =. 30 end.
        if. (day2=31)*.day1>:30 do. day2 =. 30 end.
        if. day1=31 do. day1 =. 30 end.
    else.
        day1 =. 30<.day1
        day2 =. 30<.day2
    end.
    ((360*year2-year1)+(30*month2-month1)+day2-day1),360
)
