real_text =: 3 : 0
    4 real_text y
:
    if. x=6 do.
        result =. (0j6":y)-.' '
    else.
        result =. (0j4":y)-.' '
    end.
    result =. '-'(I.result='_')}result
    if. (<result) e. '-0.0000';'-0.000000' do.
        result =. }.result
    end.
    result
)
ratio =: 4 : 0
    if. y=0 do.
        '-'
    else.
        real_text (0.0+x)%y
    end.
)
prediction =: 3 : '_1+2*y>0.0'
auc =: 3 : 0
    'labels scores' =. y
    positive =. I.labels=1
    negative =. I.labels=_1
    wins =. ties =. 0
    for_a. positive do.
        for_b. negative do.
            wins =. wins+(a{scores)>b{scores
            ties =. ties+(a{scores)=b{scores
        end.
    end.
    ((2*wins)+ties),2*(#positive)*#negative
)
confusion =: 3 : 0
    'labels predicted classes' =. y
    result =. (classes,classes)$0
    for_i. i.#labels do.
        coordinate =. <((i{labels)-1),(i{predicted)-1
        result =. (1+coordinate{result)coordinate}result
    end.
    result
)
count_margin =: 4 : '+/y<:x'
save_lines =: 4 : 0
    (;y,each<LF)1!:2 <'output/',x
)
