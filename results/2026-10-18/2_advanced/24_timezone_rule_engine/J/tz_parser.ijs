field_fail =: 3 : 0
    FieldProblem =: y
    throw.
)
line_content =: 3 : 0
    content =. (y i.'#'){.y
    while. #content do.
        if. ' '~:{:content do. break. end.
        content =. }:content
    end.
    content
)
split_fields =: 3 : 0
    fields =. ' ' split y
    fields#~0<#&>fields
)
is_number =: 4 : 0
    'low high' =. x
    (low<:#y)*.(high>:#y)*.*./y e.Digits
)
hms_value =: 4 : 0
    fields =. ':' split y
    if. (#fields)>x do. _1 return. end.
    if. -.1 2 is_number 0{::fields do. _1 return. end.
    value =. 3600*num 0{::fields
    for_index. 1+i.(#fields)-1 do.
        text =. index{::fields
        if. -.2 2 is_number text do. _1 return. end.
        part =. num text
        if. part>59 do. _1 return. end.
        unit =. 1
        if. index=1 do. unit =. 60 end.
        value =. value+unit*part
    end.
    value
)
parse_year =: 3 : 0
    if. -.4 4 is_number y do. field_fail 'bad year' end.
    value =. num y
    if. (value<1800)+.value>2099 do. field_fail 'bad year' end.
    value
)
parse_to =: 4 : 0
    if. y-:'only' do. x return. end.
    if. y-:'max' do. 2099 return. end.
    if. -.4 4 is_number y do. field_fail 'bad year' end.
    value =. num y
    if. (value<x)+.value>2099 do. field_fail 'bad year' end.
    value
)
parse_month =: 3 : 0
    month =. MonthNames i.<y
    if. month=#MonthNames do. field_fail 'bad month' end.
    month+1
)
parse_weekday =: 3 : 0
    weekday =. WeekdayNames i.<y
    if. weekday=#WeekdayNames do. field_fail 'bad day spec' end.
    weekday
)
parse_day_of_month =: 4 : 0
    if. -.1 2 is_number y do. field_fail 'bad day spec' end.
    if. '0'={.y do. field_fail 'bad day spec' end.
    day =. num y
    if. day>(x-1){CommonMonthDays do. field_fail 'bad day spec' end.
    day
)
parse_day_spec =: 4 : 0
    if. 'last'-:4{.y do. 1,(parse_weekday 4}.y),0 return. end.
    operators =. '>=';'<='
    for_index. i.2 do.
        positions =. I.(index{::operators)E.y
        if. #positions do.
            position =. {.positions
            weekday =. parse_weekday position{.y
            day =. x parse_day_of_month (position+2)}.y
            (2+index),weekday,day return.
        end.
    end.
    0 0,x parse_day_of_month y
)
parse_time =: 3 : 0
    kind =. 'w'
    if. #y do.
        if. ({:y)e.'wsu' do. kind =. {:y
            y =. }:y end.
    end.
    value =. 3 hms_value y
    if. (value<0)+.value>DaySeconds do. field_fail 'bad time' end.
    (<value),<kind
)
parse_save =: 3 : 0
    value =. 2 hms_value y
    if. (value<0)+.value>7200 do. field_fail 'bad save' end.
    value
)
parse_letter =: 3 : 0
    if. y-:'-' do. '' return. end.
    if. (0=#y)+.(5<#y)+.-.*./y e.'ABCDEFGHIJKLMNOPQRSTUVWXYZ' do. field_fail 'bad letter' end.
    y
)
parse_stdoff =: 3 : 0
    sign =. 1
    if. #y do.
        if. '-'={.y do. sign =. _1
            y =. }.y end.
    end.
    value =. 3 hms_value y
    if. (value<0)+.value>:57600 do. field_fail 'bad offset' end.
    sign*value
)
check_format =: 4 : 0
    placeholders =. +/'%s'E.y
    slashes =. +/'/'=y
    allowed =. 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-/%'
    valid =. (*./y e.allowed)*.((+/'%'=y)=placeholders)*.(placeholders<:1)*.(slashes<:1)
    valid =. valid*.-.(placeholders>0)*.slashes>0
    valid =. valid*.(x+.0=placeholders)
    if. slashes=1 do. valid =. valid*.('/'~:{.y)*.'/'~:{:y end.
    if. -.valid do. field_fail 'bad format' end.
    i.0
)
parse_until =: 3 : 0
    year_text =. 0{::y
    year =. parse_year year_text
    month_text =. 'Jan'
    if. (#y)>1 do. month_text =. 1{::y end.
    month =. parse_month month_text
    day_text =. '1'
    if. (#y)>2 do. day_text =. 2{::y end.
    day =. month parse_day_spec day_text
    time =. (<0),<'w'
    if. (#y)>3 do. time =. parse_time 3{::y end.
    'clock kind' =. time
    value =. (DaySeconds*day day_value year,month)+clock
    (<year_text),(<month_text),(<day_text),(<clock),(<kind),<value
)
