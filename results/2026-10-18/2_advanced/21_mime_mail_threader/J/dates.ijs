Weekdays =: 'mon';'tue';'wed';'thu';'fri';'sat';'sun'
Months =: 'jan';'feb';'mar';'apr';'may';'jun';'jul';'aug';'sep';'oct';'nov';'dec'
ZoneNames =: 'ut';'gmt';'z';'est';'edt';'cst';'cdt';'mst';'mdt';'pst';'pdt'
ZoneOffsets =: 0 0 0 _300 _240 _360 _300 _420 _360 _480 _420
leap =: 3 : '((0=4|y)*.0~:100|y)+.0=400|y'
month_days =: 4 : '((y-1){31 28 31 30 31 30 31 31 30 31 30 31)+(y=2)*.leap x'
has_digits =: 4 : '((#y)e.x)*.(0<#y)*.*./y e.Digits'
numeric_zone =: 3 : 0
    if. (#y)~:5 do. 0 return. end.
    (({.y)e.'+-')*.4 has_digits }.y
)
parse_date =: 3 : 0
    syntax =. (<_1),<'bad Date syntax'
    range =. (<_1),<'Date out of range'
    'okay text' =. remove_comments y
    if. -.okay do. syntax return. end.
    expanded =. ''
    for_character. text do.
        if. character=',' do. expanded =. expanded,' , '
        else. expanded =. expanded,character end.
    end.
    fields =. words expanded
    weekday =. _1
    if. (#fields)>:3 do.
        candidate =. Weekdays i.<lower 0{::fields
        if. (candidate<7)*.','-:1{::fields do. weekday =. candidate
            fields =. 2}.fields end.
    end.
    if. (#fields)~:5 do. syntax return. end.
    'daytext monthtext yeartext timetext zonetext' =. fields
    month =. 1+Months i.<lower monthtext
    pieces =. ':' split timetext
    if. (-.1 2 has_digits daytext)+.(month>12)+.-.2 4 has_digits yeartext do. syntax return. end.
    if. -.(#pieces)e.2 3 do. syntax return. end.
    for_piece. pieces do. if. -.2 has_digits >piece do. syntax return. end. end.
    numeric =. numeric_zone zonetext
    zone =. ZoneNames i.<lower zonetext
    if. (-.numeric)*.zone=#ZoneNames do. syntax return. end.
    day =. num daytext
    year =. num yeartext
    if. (#yeartext)=2 do. year =. year+1900+100*year<50 end.
    hour =. num 0{::pieces
    minute =. num 1{::pieces
    second =. 0
    if. (#pieces)=3 do. second =. num 2{::pieces end.
    if. numeric do.
        zonehour =. num 2{.}.zonetext
        zoneminute =. num 3}.zonetext
        if. (zonehour>23)+.zoneminute>59 do. range return. end.
        offset =. (60*zonehour)+zoneminute
        if. '-'={.zonetext do. offset =. -offset end.
    else. offset =. zone{ZoneOffsets end.
    if. (year<1970)+.(year>2099)+.(day<1) do. range return. end.
    if. (day>year month_days month)+.(hour>23)+.(minute>59)+.second>59 do. range return. end.
    days =. 0
    for_current. 1970+i.year-1970 do. days =. days+365+leap current end.
    for_current. 1+i.month-1 do. days =. days+year month_days current end.
    days =. days+day-1
    seconds =. (86400*days)+(3600*hour)+(60*minute)+second-60*offset
    if. seconds<0 do. range return. end.
    if. (weekday>:0)*.weekday~:7|days+3 do. (<_1),<'Date weekday mismatch' return. end.
    (<seconds),<''
)
format_utc =: 3 : 0
    days =. y div 86400
    rest =. 86400|y
    year =. 1970
    while. days>:365+leap year do. days =. days-365+leap year
        year =. year+1 end.
    month =. 1
    while. days>:year month_days month do. days =. days-year month_days month
        month =. month+1 end.
    (4 pad year),'-',(2 pad month),'-',(2 pad days+1),' ',(2 pad rest div 3600),':',(2 pad (3600|rest)div 60),':',2 pad 60|rest
)
