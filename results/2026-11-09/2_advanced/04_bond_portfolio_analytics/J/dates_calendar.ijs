BusinessDayRules =: ' ' split 'FOLLOWING MODIFIED_FOLLOWING PRECEDING UNADJUSTED'
is_leap =: 3 : '(0=4|y)*.((0~:100|y)+.0=400|y)'
year_length =: 3 : '365+is_leap y'
month_length =: 4 : 0
    if. (y=2)*.is_leap x do. 29
    else. (y-1){31 28 31 30 31 30 31 31 30 31 30 31 end.
)
split_date =: 3 : 'num&>''-'' split y'
valid_date =: 3 : 0
    'year month day' =. split_date y
    if. (year<2001)+.(year>2099)+.(month<1)+.month>12 do. 0 return. end.
    (day>:1)*.day<:year month_length month
)
day_number =: 3 : 0
    'year month day' =. y
    result =. day-1
    for_prior. 2000+i.year-2000 do. result =. result+year_length prior end.
    for_prior. >:i.month-1 do. result =. result+year month_length prior end.
    result
)
parse_date =: 3 : 'day_number split_date y'
civil_date =: 3 : 0
    year =. 2000
    while. y>:year_length year do.
        y =. y-year_length year
        year =. year+1
    end.
    month =. 1
    while. y>:year month_length month do.
        y =. y-year month_length month
        month =. month+1
    end.
    year,month,y+1
)
format_date =: 3 : 0
    'year month day' =. civil_date y
    (number year),'-',(pad2 month),'-',pad2 day
)
business_day =: 3 : '((7|y+5)<5)*.-.y e.Holidays'
business_days =: 4 : 0
    'count direction' =. x
    while. count>0 do.
        y =. y+direction
        if. business_day y do. count =. count-1 end.
    end.
    y
)
adjust_date =: 4 : 0
    if. x-:'UNADJUSTED' do. y return. end.
    direction =. 1
    if. x-:'PRECEDING' do. direction =. _1 end.
    adjusted =. y
    while. -.business_day adjusted do. adjusted =. adjusted+direction end.
    if. x-:'MODIFIED_FOLLOWING' do.
        if. (1{civil_date adjusted)~:1{civil_date y do.
            adjusted =. y
            while. -.business_day adjusted do. adjusted =. adjusted-1 end.
        end.
    end.
    adjusted
)
