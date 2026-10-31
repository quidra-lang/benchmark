fixed =: 3 : 0
    6 fixed y
:
    text =. (0j1*x)":y
    positions =. I.text~:' '
    text =. (1+({:positions)-{.positions){.({.positions)}.text
    text =. '-' (I.text='_')}text
    if. ('-'={.text)*.0=decimal text do. }.text else. text end.
)
scaled =: 3 : 0
    6 scaled y
:
    <.0.5+y*10^x
)
fraction =: 4 : 0
    divisor =. (|x)+.y
    numerator =. x div divisor
    denominator =. y div divisor
    (number numerator),'/',(number denominator),' ',4 fixed numerator%denominator
)
write_lines =: 4 : 0
    ((LF join y),LF)1!:2 <'output/',x
    i.0
)
