is_clue_line =: 3 : '(0<#y)*.*./y e.Digits,'' '''
parse_clue =: 3 : 0
    if. y-:'0' do. 0$0 return. end.
    clue =. 0$0
    for_box. ' ' split y do.
        token =. >box
        if. ((#token)<1)+.(#token)>2 do. _1 return. end.
        if. ('0'={.token)+.-.*./token e.Digits do. _1 return. end.
        clue =. clue,num token
    end.
    clue
)
run_clue =: 3 : 0
    clue =. 0$0
    run =. 0
    for_state. y do.
        if. state=Filled do. run =. run+1
        elseif. run>0 do. clue =. clue,run
            run =. 0 end.
    end.
    if. run>0 do. clue =. clue,run end.
    clue
)
clue_text =: 4 : 0
    if. #y do. x join number&.><"0 y else. '0' end.
)
clue_span =: 3 : '(+/y)+(#y)-1'
clue_fits =: 4 : '(clue_span x)<:y'
