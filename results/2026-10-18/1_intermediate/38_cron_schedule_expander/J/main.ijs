LF =: 10{a.
Digits =: '0123456789'
Lower =: 'abcdefghijklmnopqrstuvwxyz'
Fields =: 'minute';'hour';'day-of-month';'month';'day-of-week'
Low =: 0 0 1 1 0
High =: 59 23 31 12 7
MonthCodes =: ;:'JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC'
WeekCodes =: ;:'SUN MON TUE WED THU FRI SAT'
Months =: ;:'January February March April May June July August September October November December'
Weekdays =: ;:'Sunday Monday Tuesday Wednesday Thursday Friday Saturday'
WeekShort =: ;:'Sun Mon Tue Wed Thu Fri Sat'
Ordinals =: '1st';'2nd';'3rd';'4th';'5th'
Macros =: '@yearly';'@annually';'@monthly';'@weekly';'@daily';'@midnight';'@hourly'
MacroText =: '0 0 1 1 *';'0 0 1 1 *';'0 0 1 * *';'0 0 * * 0';'0 0 * * *';'0 0 * * *';'0 * * * *'
Commands =: ;:'JOB VALIDATE REMOVE RENAME ENABLE DISABLE RUNTIME LIST EXPAND DESCRIBE MATCH NEXT PREV COUNT GAP OVERLAP TIMELINE CONFLICTS WEEK CALENDAR SIMULATE EXCLUDE INCLUDE HOLIDAYS'
Arity =: _2 _1 1 2 1 1 3 0 2 1 3 4 4 5 3 6 4 4 1 2 4 1 1 0
Forms =: 'newid expr';'expr';'id';'id newid';'id';'id';'id duration policy';'';'id field';'id';'id datetime';'id datetime count';'id datetime count';'id datetime datetime';'id datetime';'id id datetime datetime';'datetime datetime';'datetime datetime';'date';'id month';'datetime datetime';'date';'date';''
Jobs =: 0 10$a:
Holidays =: i.0
Error =: ''
number =: 3 : ',''0'' 8!:2 y'
two =: 3 : '_2{.''00'',number y'
div =: 4 : '<.x%x:y'
split =: 4 : '<;._1 x,y'
words =: 3 : 0
    parts =. ' ' split y
    parts#~0<#&>parts
)
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
digits =: 3 : '(0<#y)*.*./y e.Digits'
small =: 3 : '((#y)e.1 2)*.digits y'
emit =: 3 : 'Output =: Output,<y'
fail =: 3 : 0
    Error =: y
    throw.
)
field_fail =: 4 : 'fail (x{::Fields),'' '',y'
histogram =: 4 : 0
    result =. x#0
    if. #y do. result =. (#/.~y) (~.y)}result end.
    result
)

leap =: 3 : '((0=4|y)*.0~:100|y)+.0=400|y'
month_days =: 3 : 0
    'year month' =. y
    ((month-1){31 28 31 30 31 30 31 31 30 31 30 31)+(month=2)*leap year
)
make_calendar =: 3 : 0
    Calendar =: 0 3$0
    for_year. 2000+i.100 do.
        for_month. 1+i.12 do.
            count =. month_days year,month
            Calendar =: Calendar,((count#year),.(count#month)),.1+i.count
        end.
    end.
    Calendar =: Calendar,2100 1 1
)
weekday =: 3 : '7|y+6'
date_plain =: 3 : 0
    'year month day' =. y{Calendar
    (number year),'-',(two month),'-',two day
)
date_text =: 3 : '(date_plain y),'' '',(weekday y){::WeekShort'
clock_text =: 3 : '(two y div 60),'':'',two 60|y'
datetime =: 3 : 0
    day =. y div 1440
    (date_plain day),' ',(clock_text 1440|y),' ',(weekday day){::WeekShort
)
span =: 3 : '(number y div 1440),''d'',(two (1440|y) div 60),''h'',(two 60|y),''m'''
parse_date =: 4 : 0
    if. 10~:#y do. fail x end.
    if. -.'--'-:4 7{y do. fail x end.
    if. -.digits 0 1 2 3 5 6 8 9{y do. fail x end.
    year =. 0".4{.y
    month =. 0".2{.5}.y
    day =. 0".8}.y
    if. (year<2001)+.(year>2098)+.(month<1)+.month>12 do. fail x end.
    if. (day<1)+.day>month_days year,month do. fail x end.
    Calendar i.year,month,day
)
parse_time =: 3 : 0
    if. 5~:#y do. fail 'invalid datetime' end.
    if. ':'~:2{y do. fail 'invalid datetime' end.
    if. -.digits 0 1 3 4{y do. fail 'invalid datetime' end.
    hour =. 0".2{.y
    minute =. 0".3}.y
    if. (hour>23)+.minute>59 do. fail 'invalid datetime' end.
    (60*hour)+minute
)
parse_month =: 3 : 0
    if. 7~:#y do. fail 'invalid month' end.
    if. '-'~:4{y do. fail 'invalid month' end.
    if. -.digits 0 1 2 3 5 6{y do. fail 'invalid month' end.
    year =. 0".4{.y
    month =. 0".5}.y
    if. (year<2001)+.(year>2098)+.(month<1)+.month>12 do. fail 'invalid month' end.
    Calendar i.year,month,1
)

field_value =: 4 : 0
    if. x=3 do.
        index =. MonthCodes i.<y
        if. index<12 do. index+1 return. end.
    elseif. x=4 do.
        index =. WeekCodes i.<y
        if. index<7 do. index return. end.
    end.
    if. -.small y do. x field_fail 'invalid value' end.
    value =. 0".y
    if. (value<x{Low)+.value>x{High do. x field_fail 'out of range' end.
    value
)
parse_field =: 4 : 0
    values =. i.0
    specials =. 0$a:
    for_item. ',' split y do.
        item =. >item
        if. 0=#item do. x field_fail 'empty item' end.
        special =. ''
        if. (x=2)*.('L'={.item)+.'W'={:item do.
            if. (<item)e.'L';'LW' do.
                special =. item
            elseif. 'L-'-:2{.item do.
                part =. 2}.item
                if. -.small part do. x field_fail 'invalid value' end.
                value =. 0".part
                if. (value<1)+.value>30 do. x field_fail 'out of range' end.
                special =. 'L-',number value
            elseif. 'W'={:item do.
                part =. }:item
                if. -.small part do. x field_fail 'invalid value' end.
                value =. 0".part
                if. (value<1)+.value>31 do. x field_fail 'out of range' end.
                special =. (number value),'W'
            else. x field_fail 'invalid value' end.
        elseif. (x=4)*.'#'e.item do.
            position =. item i.'#'
            value =. x field_value position{.item
            part =. (position+1)}.item
            if. (1~:#part)+.-.digits part do. x field_fail 'invalid value' end.
            nth =. 0".part
            if. (nth<1)+.nth>5 do. x field_fail 'out of range' end.
            special =. (number 7|value),'#',number nth
        elseif. (x=4)*.(2<:#item)*.'L'={:item do.
            value =. x field_value }:item
            special =. (number 7|value),'L'
        else.
            slash =. item i.'/'
            has_step =. slash<#item
            base =. slash{.item
            if. '*'-:base do.
                a =. x{Low
                b =. x{High
            elseif. '-'e.base do.
                dash =. base i.'-'
                a =. x field_value dash{.base
                b =. x field_value (dash+1)}.base
                if. a>b do. x field_fail 'invalid range' end.
            else.
                a =. x field_value base
                b =. a
                if. has_step do. b =. x{High end.
            end.
            step =. 1
            if. has_step do.
                part =. (slash+1)}.item
                if. -.small part do. x field_fail 'invalid step' end.
                step =. 0".part
                if. step=0 do. x field_fail 'invalid step' end.
            end.
            added =. a+step*i.1+(b-a) div step
            if. x=4 do. added =. 7|added end.
            values =. values,added
        end.
        if. #special do.
            if. -.(<special)e.specials do. specials =. specials,<special end.
        end.
    end.
    (</:~~.values),<specials
)
parse_cron =: 3 : 0
    fields =. y
    if. 1=#fields do.
        if. '@'={.0{::fields do.
            index =. Macros i.0{fields
            if. index=#Macros do. fail 'unknown macro' end.
            fields =. words index{::MacroText
        end.
    end.
    if. 5~:#fields do. fail 'field count' end.
    sets =. specials =. 0$a:
    for_kind. i.5 do.
        parsed =. kind parse_field kind{::fields
        sets =. sets,0{parsed
        specials =. specials,1{parsed
    end.
    either =. ('*'~:{.2{::fields)*.'*'~:{.4{::fields
    times =. ,(60*1{::sets)+/0{::sets
    (<fields),(<sets),(<specials),(<either),<times
)

nearest_weekday =: 4 : 0
    'first length' =. x
    day =. y
    select. weekday first+day-1
    case. 6 do. if. day=1 do. 3 else. day-1 end.
    case. 0 do. if. day=length do. day-2 else. day+1 end.
    case. do. day
    end.
)
day_status =: 4 : 0
    sets =. 3{::x
    specials =. 4{::x
    'year month day' =. y{Calendar
    length =. month_days year,month
    first =. 1+y-day
    week =. weekday y
    dom =. day e.2{::sets
    dow =. week e.4{::sets
    for_special. 2{::specials do.
        special =. >special
        if. 'L'-:special do.
            dom =. dom+.day=length
        elseif. 'LW'-:special do.
            dom =. dom+.day=(first,length) nearest_weekday length
        elseif. 'L-'-:2{.special do.
            dom =. dom+.day=length-0".2}.special
        else.
            nearest =. 0".}:special
            if. nearest<:length do. dom =. dom+.day=(first,length) nearest_weekday nearest end.
        end.
    end.
    for_special. 4{::specials do.
        special =. >special
        value =. 0".{.special
        if. '#'e.special do.
            nth =. 0".2}.special
            dow =. dow+.((week=value)*.nth=1+(day-1) div 7)
        else.
            dow =. dow+.((week=value)*.(day+7)>length)
        end.
    end.
    if. 5{::x do. condition =. dom+.dow else. condition =. dom*.dow end.
    (month e.3{::sets),dom,dow,condition
)
scheduled =: 4 : 0
    status =. x day_status y
    (0{status)*.3{status
)
fire_times =: 4 : 0
    'lo hi limit reverse' =. y
    days =. (lo div 1440)+i.1+(hi div 1440)-lo div 1440
    daily =. 6{::x
    if. reverse do. days =. |.days [ daily =. |.daily end.
    result =. i.0
    for_day. days do.
        if. day e.Holidays do. continue. end.
        if. -.x scheduled day do. continue. end.
        times =. (1440*day)+daily
        result =. result,times#~(lo<:times)*.times<:hi
        if. limit<:#result do. limit{.result return. end.
    end.
    result
)

list_text =: 4 : 0
    if. 0=#y do. '' return. end.
    if. 1=#y do. 0{::y return. end.
    (', ' join }:y),' ',x,' ',_1{::y
)
value_label =: 4 : 0
    select. x
    case. 3 do. (y-1){::Months
    case. 4 do. y{::Weekdays
    case. do. number y
    end.
)
run_labels =: 4 : 0
    result =. 0$a:
    start =. 0
    while. start<#y do.
        finish =. start+1
        while. finish<#y do.
            if. (finish{y)~:1+(finish-1){y do. break. end.
            finish =. finish+1
        end.
        if. 3<:finish-start do.
            result =. result,<(x value_label start{y),' through ',x value_label (finish-1){y
        else.
            for_value. (finish-start){.start}.y do.
                result =. result,<x value_label value
            end.
        end.
        start =. finish
    end.
    result
)
stepped =: 4 : 0
    if. 2>#y do. 0 return. end.
    step =. 1{y
    if. (0~:{.y)+.step<2 do. 0 return. end.
    if. y-:step*i.1+x div step do. step else. 0 end.
)
dom_clause =: 3 : 0
    values =. 2{::3{::y
    specials =. 2{::4{::y
    parts =. 0$a:
    if. #values do.
        if. 1=#values do.
            parts =. <'day ',number {.values
        else.
            parts =. <'days ','and' list_text 2 run_labels values
        end.
    end.
    for_special. specials do.
        special =. >special
        if. 'L'-:special do. part =. 'the last day'
        elseif. 'LW'-:special do. part =. 'the last weekday'
        elseif. 'L-'-:2{.special do.
            count =. 0".2}.special
            if. count=1 do. part =. '1 day before the last day'
            else. part =. (number count),' days before the last day' end.
        else. part =. 'the weekday nearest day ',}:special end.
        parts =. parts,<part
    end.
    ('and' list_text parts),' of the month'
)
dow_clause =: 4 : 0
    values =. 4{::3{::y
    specials =. 4{::4{::y
    parts =. 0$a:
    if. #values do. parts =. <x list_text 4 run_labels values end.
    for_special. specials do.
        special =. >special
        name =. (0".{.special){::Weekdays
        if. '#'e.special do.
            ordinal =. (<:0".2}.special){::Ordinals
            part =. 'the ',ordinal,' ',name
        else. part =. 'the last ',name end.
        parts =. parts,<part
    end.
    result =. x list_text parts
    if. #specials do. result =. result,' of the month' end.
    result
)
describe =: 3 : 0
    sets =. 3{::y
    minutes =. 0{::sets
    hours =. 1{::sets
    times =. 6{::y
    if. 4>:#times do.
        result =. 'At ','and' list_text clock_text&.><"0 times
    else.
        ms =. 59 stepped minutes
        hs =. 23 stepped hours
        if. 60=#minutes do. result =. 'Every minute'
        elseif. ms do. result =. 'Every ',(number ms),' minutes'
        elseif. 1=#minutes do. result =. 'At minute ',number {.minutes
        else. result =. 'At minutes ','and' list_text 0 run_labels minutes end.
        if. (24=#hours)*.'At minute'-:9{.result do.
            result =. result,' of every hour'
        elseif. 24=#hours do.
        elseif. hs do. result =. result,', every ',(number hs),' hours'
        elseif. hours-:({.hours)+i.#hours do.
            result =. result,', between ',(two {.hours),':00 and ',(two {:hours),':59'
        else. result =. result,', during hours ','and' list_text 1 run_labels hours end.
    end.
    dfull =. 31=#2{::sets
    ufull =. 7=#4{::sets
    if. 5{::y do.
        if. -.dfull+.ufull do. result =. result,', on ',(dom_clause y),' or on ','and' dow_clause y end.
    elseif. (-.dfull)*.-.ufull do.
        result =. result,', on ',(dom_clause y),' if it is ','or' dow_clause y
    elseif. -.dfull do. result =. result,', on ',dom_clause y
    elseif. -.ufull do. result =. result,', on ','and' dow_clause y
    end.
    if. 12~:#3{::sets do. result =. result,', in ','and' list_text 3 run_labels 3{::sets end.
    result
)

job_index =: 3 : 0
    index =. (0{"1 Jobs)i.<y
    if. index=#Jobs do. fail 'unknown job' end.
    index
)
new_id =: 3 : 0
    if. (16<#y)+.0=#y do. fail 'invalid id' end.
    if. (-.({.y)e.Lower)+.-.*./y e.Lower,Digits,'_' do. fail 'invalid id' end.
    if. (<y)e.0{"1 Jobs do. fail 'duplicate job' end.
    y
)
bounded =: 4 : 0
    'width maximum label' =. x
    if. ((#y)>width)+.-.digits y do. fail 'invalid ',label end.
    if. '0'={.y do. fail 'invalid ',label end.
    value =. 0".y
    if. value>maximum do. fail 'invalid ',label end.
    value
)
parse_arguments =: 4 : 0
    position =. 0
    result =. 0$a:
    for_form. words x{::Forms do.
        form =. >form
        token =. position{::y
        used =. 1
        select. form
        case. 'id' do. value =. job_index token
        case. 'newid' do. value =. new_id token
        case. 'expr' do.
            value =. parse_cron position}.y
            used =. (#y)-position
        case. 'field' do.
            value =. Fields i.<token
            if. value=5 do. fail 'invalid field' end.
        case. 'date' do. value =. 'invalid date' parse_date token
        case. 'datetime' do.
            day =. 'invalid datetime' parse_date token
            time =. parse_time (position+1){::y
            value =. (1440*day)+time
            used =. 2
        case. 'month' do. value =. parse_month token
        case. 'count' do. value =. (2;50;'count') bounded token
        case. 'duration' do. value =. (4;1440;'duration') bounded token
        case. 'policy' do.
            if. -.(<token)e.;:'ALLOW FORBID REPLACE' do. fail 'invalid policy' end.
            value =. token
        end.
        result =. result,<value
        position =. position+used
    end.
    if. x e.13 15 16 17 20 do.
        'lo hi' =. >_2{.result
        if. lo>hi do. fail 'invalid window' end.
        if. 44640<hi-lo do. fail 'window too long' end.
    end.
    result
)
sorted_jobs =: 3 : '/:s:0{"1 Jobs'
enabled_jobs =: 3 : 0
    order =. sorted_jobs ''
    order#~>7{"1 order{Jobs
)

fire_table =: 3 : 0
    'lo hi' =. y
    selected =. enabled_jobs ''
    table =. ((#selected),1+hi-lo)$0
    for_i. i.#selected do.
        times =. ((i{selected){Jobs) fire_times lo,hi,44641,0
        row =. (1+hi-lo)#0
        row =. 1 (times-lo)}row
        table =. row i}table
    end.
    (<selected),<table
)
simulation =: 3 : 0
    'lo hi' =. y
    selected =. enabled_jobs ''
    width =. 1441+hi-lo
    changes =. width#0
    rows =. 0$a:
    for_index. selected do.
        job =. index{Jobs
        policy =. 9{::job
        duration =. 8{::job
        times =. job fire_times lo,hi,44641,0
        starts =. ends =. i.0
        skipped =. replaced =. 0
        if. 'FORBID'-:policy do.
            for_time. times do.
                if. #ends do.
                    if. time<{:ends do.
                        skipped =. skipped+1
                        continue.
                    end.
                end.
                starts =. starts,time
                ends =. ends,time+duration
            end.
        else.
            starts =. times
            ends =. times+duration
            if. ('REPLACE'-:policy)*.1<#starts do.
                replaced =. +/(}:ends)>}.starts
                ends =. ((}:ends)<.}.starts),{:ends
            end.
        end.
        changes =. changes+(width histogram starts-lo)-width histogram ends-lo
        rows =. rows,<(0{::job),' ',policy,' started ',(number #starts),' skipped ',(number skipped),' replaced ',(number replaced),' busy ',number +/ends-starts
    end.
    running =. +/\changes
    peak =. >./running
    header =. 'SIMULATE ',(number #selected),' peak ',number peak
    if. peak do. header =. header,' at ',datetime lo+running i.peak end.
    (<header),rows
)

execute =: 3 : 0
    tokens =. words y
    command =. 0{::tokens
    kind =. Commands i.<command
    if. kind=#Commands do. fail 'unknown command' end.
    argv =. }.tokens
    expected =. kind{Arity
    if. expected<0 do.
        if. (#argv)<-expected do. fail 'wrong arguments' end.
    elseif. expected~:#argv do. fail 'wrong arguments' end.
    args =. kind parse_arguments argv
    Output =: 0$a:
    if. kind e.2 3 4 5 6 8 9 10 11 12 13 14 15 19 do.
        index =. 0{::args
        job =. index{Jobs
        id =. 0{::job
    end.
    select. kind
    case. 0 do.
        id =. 0{::args
        cron =. 1{::args
        job =. (<id),(< ' ' join }.argv),cron,(<1),(<1),<'ALLOW'
        Jobs =: Jobs,1 10$job
        emit 'JOB ',id,' added'
    case. 1 do.
        cron =. 0{::args
        rule =. 'AND'
        if. 3{::cron do. rule =. 'OR' end.
        emit 'VALID ',(' ' join 0{::cron),' ',rule,' ',number #4{::cron
    case. 2 do.
        Jobs =: ((i.#Jobs)-.index){Jobs
        emit 'REMOVE ',id
    case. 3 do.
        new =. 1{::args
        Jobs =: (<new) (<index,0)}Jobs
        emit 'RENAME ',id,' ',new
    case. 4;5 do.
        enabled =. kind=4
        if. enabled=7{::job do.
            if. enabled do. fail 'already enabled' else. fail 'already disabled' end.
        end.
        Jobs =: (<enabled) (<index,7)}Jobs
        emit command,' ',id
    case. 6 do.
        job =. (1 2{args) 8 9}job
        Jobs =: job index}Jobs
        emit 'RUNTIME ',id,' ',(number 8{::job),' ',9{::job
    case. 7 do.
        emit 'LIST ',number #Jobs
        for_i. sorted_jobs '' do.
            row =. i{Jobs
            state =. 'off'
            if. 7{::row do. state =. 'on' end.
            emit (0{::row),' ',state,' ',(number 8{::row),' ',(9{::row),' ',1{::row
        end.
    case. 8 do.
        field =. 1{::args
        values =. field{::3{::job
        specials =. field{::4{::job
        line =. 'EXPAND ',id,' ',(field{::Fields),' ',number #values
        parts =. (number&.><"0 values),specials
        if. #parts do. line =. line,' ',' ' join parts end.
        emit line
    case. 9 do. emit 'DESCRIBE ',id,' ',describe job
    case. 10 do.
        time =. 1{::args
        day =. time div 1440
        status =. job day_status day
        sets =. 3{::job
        reasons =. (-.(60|time)e.0{::sets),-.((1440|time) div 60)e.1{::sets
        reasons =. reasons,((-.3{status)*.-.1{status),(-.0{status),((-.3{status)*.-.2{status),day e.Holidays
        line =. 'MATCH ',id,' ',datetime time
        if. +./reasons do. emit line,' no ',' ' join reasons#Fields,<'excluded'
        else. emit line,' yes' end.
    case. 11;12 do.
        base =. 1{::args
        count =. 2{::args
        if. kind=11 do.
            times =. job fire_times (base+1),(base+527040),count,0
            sign =. '+'
        else.
            times =. job fire_times (base-527040),(base-1),count,1
            sign =. '-'
        end.
        emit command,' ',id,' ',number #times
        for_time. times do. emit (datetime time),' ',sign,span |time-base end.
        if. count>#times do. emit 'NONE' end.
    case. 13 do.
        times =. job fire_times (1{::args),(2{::args),44641,0
        emit 'COUNT ',id,' runs ',(number #times),' days ',number #~.times div 1440
    case. 14 do.
        base =. 1{::args
        times =. job fire_times base,(base+44640),44641,0
        line =. 'GAP ',id,' runs ',number #times
        if. 2>#times do. emit line,' none'
        else.
            gaps =. (}.times)-}:times
            longest =. >./gaps
            first =. gaps i.longest
            emit line,' shortest ',(span <./gaps),' longest ',(span longest),' from ',(datetime first{times),' to ',datetime (first+1){times
            for_gap. /:~~.gaps do. emit (span gap),' ',number +/gap=gaps end.
        end.
    case. 15 do.
        other =. (1{::args){Jobs
        window =. (2{::args),(3{::args),44641,0
        left =. job fire_times window
        right =. other fire_times window
        common =. left#~left e.right
        line =. 'OVERLAP ',id,' ',(0{::other),' ',number #common
        if. #common do. line =. line,' first ',(datetime {.common),' last ',datetime {:common end.
        emit line
    case. 16 do.
        'lo hi' =. >args
        'selected table' =. fire_table lo,hi
        pairs =. I.,|:table
        emit 'TIMELINE ',number #pairs
        for_pair. (100<.#pairs){.pairs do.
            time =. lo+pair div #selected
            row =. ((#selected)|pair){selected
            emit (datetime time),' ',0{::row{Jobs
        end.
        if. 100<#pairs do. emit '... ',(number (#pairs)-100),' more' end.
    case. 17 do.
        'lo hi' =. >args
        'selected table' =. fire_table lo,hi
        counts =. +/table
        conflicts =. I.counts>:2
        peak =. 0
        if. #conflicts do. peak =. >./counts end.
        emit 'CONFLICTS ',(number #conflicts),' peak ',number peak
        for_time. (100<.#conflicts){.conflicts do.
            at =. selected#~time{"1 table
            emit (datetime lo+time),' ',(number time{counts),' ',' ' join 0{"1 at{Jobs
        end.
        if. 100<#conflicts do. emit '... ',(number (#conflicts)-100),' more' end.
    case. 18 do.
        day =. 0{::args
        lo =. 1440*day
        hours =. 168#0
        for_i. enabled_jobs '' do.
            times =. (i{Jobs) fire_times lo,(lo+10079),10080,0
            hours =. hours+168 histogram (times-lo) div 60
        end.
        emit 'WEEK ',(0{::argv),' ',number +/hours
        for_i. i.7 do.
            counts =. 24{.(24*i)}.hours
            marks =. (10<.counts){'.123456789+'
            emit (date_text day+i),' ',marks,' ',number +/counts
        end.
    case. 19 do.
        first =. 1{::args
        length =. month_days 2{.first{Calendar
        cells =. (weekday first)#<'...'
        count =. 0
        for_day. i.length do.
            date =. first+day
            mark =. '-'
            if. job scheduled date do.
                if. date e.Holidays do. mark =. 'x'
                else. mark =. '*' [ count =. count+1 end.
            end.
            cells =. cells,<(two day+1),mark
        end.
        cells =. cells,(7|-#cells)#<'...'
        emit 'CALENDAR ',id,' ',(1{::argv),' days ',(number count),' runs ',number count*#6{::job
        emit 'Sun Mon Tue Wed Thu Fri Sat'
        for_start. 7*i.(#cells) div 7 do. emit ' ' join 7{.start}.cells end.
    case. 20 do. Output =: simulation >args
    case. 21;22 do.
        day =. 0{::args
        if. kind=21 do.
            if. day e.Holidays do. fail 'already excluded' end.
            Holidays =: /:~Holidays,day
        else.
            if. -.day e.Holidays do. fail 'not excluded' end.
            Holidays =: Holidays-.day
        end.
        emit command,' ',(date_text day),' holidays ',number #Holidays
    case. 23 do.
        emit 'HOLIDAYS ',number #Holidays
        for_day. Holidays do. emit date_text day end.
    end.
    Output
)

main =: 3 : 0
    count =. 0".1!:1[3
    make_calendar ''
    for_command. i.count do.
        line =. 1!:1[3
        try. rows =. execute line
        catcht. rows =. <'ERROR ',Error end.
        for_row. rows do. ((>row),LF) 1!:2[4 end.
    end.
)
main ''
2!:55[0
