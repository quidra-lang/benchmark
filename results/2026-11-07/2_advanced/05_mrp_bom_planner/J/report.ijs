money =: 3 : '(number y div 100),''.'',pad2 100|y'
percent =: 4 : '((200*x)+y) div 2*y'
table_row =: 4 : 0
    'values width' =. y
    line =. x,(10-#x)#' '
    for_value. values do.
        text =. number value
        line =. line,((width-#text)#' '),text
    end.
    line
)
write_report =: 4 : 0
    text =. ''
    for_box. y do. text =. text,(>box),LF end.
    text 1!:2 <'output/',x
    i.0
)
