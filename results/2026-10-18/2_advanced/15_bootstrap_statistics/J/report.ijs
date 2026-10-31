real_text =: 3 : 0
    text =. 0j4":y
    positions =. I.text~:' '
    text =. (1+({:positions)-{.positions){.({.positions)}.text
    text =. '-' (I.text='_')}text
    if. text-:'-0.0000' do. '0.0000' else. text end.
)
p_value =: 4 : 0
    'numerator denominator' =. reduced_fraction x,y
    (number numerator),'/',(number denominator),' ',real_text numerator%denominator
)
number_list =: 3 : 0
    if. 0=#y do. 'none' return. end.
    text_line <"0 /:~y
)
bin_number =: 4 : 0
    'value low high' =. y
    (x-1)<.<.(x*(value-low))%high-low
)
bar =: 4 : '''#''#~((40*x)+y-1) div y'
write_lines =: 4 : 0
    ((LF join y),LF)1!:2 <'output/',x
    i.0
)
