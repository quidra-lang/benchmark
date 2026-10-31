integer =: 3 : 0
    text =. ,":y
    '-'(I.text='_')}text
)
finite =: 3 : '0<#y'
digits =: 3 : '(0<#y)*.*./y e.''0123456789'''
read_number =: 4 : 0
    text =. y
    sign =. 1x
    if. 0=#text do. '' return. end.
    if. x*. '-'={.text do.
        sign =. _1x
        text =. }.text
    end.
    if. digits text do. sign*".text,'x' return. end.
    marks =. I.text e.'./'
    if. 1~:#marks do. '' return. end.
    split =. {.marks
    first =. split{.text
    second =. (split+1)}.text
    if. -. (digits first)*.digits second do. '' return. end.
    numerator =. ".first,'x'
    denominator =. ".second,'x'
    if. '.'=split{text do.
        denominator =. 10x^#second
    elseif. denominator=0 do.
        '' return.
    end.
    sign*numerator%denominator
)
fraction =: 3 : 0
    if. -.finite y do. ,'-' return. end.
    'numerator denominator' =. 2 x:y
    if. denominator=1 do.
        integer numerator
    else.
        (integer numerator),'/',integer denominator
    end.
)
approximate =: 3 : 0
    scaled =. <.(1000000x*|y)+1r2
    sign =. ''
    if. (y<0)*.scaled>0 do. sign =. ,'-' end.
    whole =. integer <.scaled%1000000x
    digits_text =. integer 1000000x|scaled
    sign,whole,'.',(-6){.'000000',digits_text
)
endpoint =: 4 : 0
    if. finite y do.
        fraction y
    elseif. x do.
        '-inf'
    else.
        'inf'
    end.
)
