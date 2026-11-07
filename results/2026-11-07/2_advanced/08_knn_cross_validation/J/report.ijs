fixed =: 4 : 0
    scale =. 1
    for_index. i.x do. scale =. scale*10 end.
    rounded =. <.!.0 ((|y)*scale)+0.5
    text =. (number rounded div scale),'.',(-x){.(x#'0'),number scale|rounded
    if. (y<!.0 0)*.rounded~:0 do. '-',text else. text end.
)
f4 =: 3 : '4 fixed y'
four_decimal =: 3 : '(*y)*<.!.0 ((|y)*10000.0)+0.5'
ratio_text =: 4 : '(number x),''/'',(number y),'' '',f4 (real x)%real y'
fraction_text =: 4 : 0
    if. y=0 do. '- -' return. end.
    divisor =. x+.y
    (number x div divisor),'/',(number y div divisor),' ',f4 (real x)%real y
)
text_line =: 3 : 0
    fields =. 0$a:
    for_box. y do.
        value =. >box
        if. 2~:3!:0 value do. value =. number value end.
        fields =. fields,<value
    end.
    ' ' join fields
)
add_line =: 3 : 0
    ReportLines =: ReportLines,<text_line y
    i.0
)
next_part =: 3 : 0
    if. #ReportLines do. ReportLines =: ReportLines,<'' end.
    i.0
)
write_lines =: 4 : 0
    ((LF join y),LF) 1!:2 <'output/',x
    i.0
)
