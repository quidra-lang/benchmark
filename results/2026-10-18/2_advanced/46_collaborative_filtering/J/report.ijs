real_text =: 3 : 0
    text =. (0j4":y)-.' '
    text =. '-'(I.text='_')}text
    if. text-:'-0.0000' do.
        text =. '0.0000'
    end.
    text
)
optional_real =: 4 : 0
    if. y do.
        real_text x
    else.
        '-'
    end.
)
save_lines =: 4 : 0
    contents =. ''
    for_line. y do.
        contents =. contents,(>line),LF
    end.
    contents 1!:2 <'output/',x
)
