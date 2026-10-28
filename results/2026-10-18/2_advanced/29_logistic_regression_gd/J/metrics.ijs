fixed =: 4 : 0
    result =. (0 j.x)":y
    result =. result#~result~:' '
    if. 0=0".result do.
        if. '_'={.result do.
            result =. }.result
        end.
    end.
    '-'(I.result='_')}result
)
ratio =: 4 : 0
    if. y=0 do.
        '-' return.
    end.
    rounded =. ((20000*x)+y)intdiv 2*y
    part =. _4{.'0000',":10000|rounded
    (":rounded intdiv 10000),'.',part
)
fraction =: 3 : 0
    'numerator denominator' =. y
    divisor =. numerator+.denominator
    (":numerator intdiv divisor),'/',(":denominator intdiv divisor),' ',numerator ratio denominator
)
confusion =: 4 : 0
    tp =. +/(x=1)*.y=1
    fp =. +/(x=1)*.y=0
    tn =. +/(x=0)*.y=0
    fn =. +/(x=0)*.y=1
    tp,fp,tn,fn
)
auc =: 4 : 0
    order =. /:x
    positives =. +/y
    negatives =. (#y)-positives
    rank_sum =. start =. 0
    while. start<#order do.
        finish =. start
        while. (finish+1)<#order do.
            if. (((finish+1){order){x)~:(start{order){x do.
                break.
            end.
            finish =. finish+1
        end.
        for_position. start+i.1+finish-start do.
            if. 1=(position{order){y do.
                rank_sum =. rank_sum+start+finish+2
            end.
        end.
        start =. finish+1
    end.
    (rank_sum-positives*(positives+1)),2*positives*negatives
)
roc_points =: 4 : 0
    order =. \:x
    result =. 0$a:
    tp =. fp =. 0
    for_position. i.#order do.
        index =. position{order
        if. 1=index{y do.
            tp =. tp+1
        else.
            fp =. fp+1
        end.
        emit =. position=<:#order
        if. -.emit do.
            emit =. (index{x)~:((position+1){order){x
        end.
        if. emit do.
            result =. result,<(<index{x),(<tp),<fp
        end.
    end.
    result
)
rp_threshold =: 0&{::
rp_tp =: 1&{::
rp_fp =: 2&{::
