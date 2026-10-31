pad =: 4 : 0
    text =. number y
    ((0>.x-#text)$'0'),text
)
local_text =: 3 : 0
    'year month day hour minute second' =. split_time y
    (4 pad year),'-',(2 pad month),'-',(2 pad day),'T',(2 pad hour),':',(2 pad minute),':',2 pad second
)
ut_text =: 3 : '(local_text y),''Z'''
offset_text =: 3 : 0
    sign =. '+'
    if. y<0 do. sign =. '-'
        y =. -y end.
    text =. sign,(2 pad y div 3600),':',2 pad 60|y div 60
    if. 60|y do. text =. text,':',2 pad 60|y end.
    text
)
duration_text =: 3 : 0
    sign =. ''
    if. y<0 do. sign =. '-'
        y =. -y end.
    sign,(number y div 3600),':',(2 pad 60|y div 60),':',2 pad 60|y
)
clock_text =: 3 : 0
    text =. (number y div 3600),':',2 pad 60|y div 60
    if. 60|y do. text =. text,':',2 pad 60|y end.
    text
)
state_text =: 3 : 0
    kind =. 'STD'
    if. 2{::y do. kind =. 'DST' end.
    (offset_text 1{::y),' ',kind,' ',3{::y
)
change_text =: 3 : 0
    'time before after' =. y
    (ut_text time),' ',(state_text before),' -> ',state_text after
)
write_lines =: 4 : 0
    text =. ''
    for_line. y do. text =. text,(>line),LF end.
    text 1!:2 <x
)
write_blocks =: 4 : 0
    lines =. 0$a:
    for_index. i.#y do.
        if. index do. lines =. lines,<'' end.
        lines =. lines,index{::y
    end.
    x write_lines lines
)
