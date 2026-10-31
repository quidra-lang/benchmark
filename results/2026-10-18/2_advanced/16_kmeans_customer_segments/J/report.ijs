real_text =: 3 : 0
    text =. 0j4":y
    positions =. I.text~:' '
    text =. (1+({:positions)-{.positions){.({.positions)}.text
    text =. '-' (I.text='_')}text
    if. text-:'-0.0000' do. '0.0000' else. text end.
)
reals =: 3 : ''' '' join real_text&.><"0 y'
four_decimal =: 3 : '<.0.5+10000*y'
amount =: 3 : 0
    sign =. ''
    if. y<0 do. sign =. '-' end.
    value =. |y
    cents =. number 100|value
    sign,(number value div 100),'.',((_2{.'00',cents))
)
write_lines =: 4 : 0
    ((LF join y),LF)1!:2 <'output/',x
    i.0
)
