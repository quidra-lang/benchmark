cross =: 3 : 0
    'origin first second' =. y
    a =. first-origin
    b =. second-origin
    ((0{a)*1{b)-(1{a)*0{b
)
along =: 4 : 0
    'first second' =. x
    first+y*second-first
)
point_key =: 3 : '|.y'
fraction_text =: 3 : 0
    'numerator denominator' =. 2 x:y
    text =. integer numerator
    if. denominator~:1 do.
        text =. text,'/',integer denominator
    end.
    text
)
point_text =: 3 : '''('',(fraction_text 0{y),'','',(fraction_text 1{y),'')'''
segment_text =: 3 : '(point_text 0{y),''-'',point_text 1{y'
real =: 3 : 0
    'numerator denominator' =. 2 x:y
    (0.0+_1 x:numerator)%0.0+_1 x:denominator
)
format_real =: 4 : 0
    text =. (0 j.x)":y
    '-'(I.text='_')}text
)
