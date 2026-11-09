smo_count =: 3 : 'SMCounts =: (1+y{SMCounts)y}SMCounts'
smo_nonbound =: 3 : '(0<y{SMAlpha)*.SMC>y{SMAlpha'
smo_snap =: 3 : 0
    if. y<0.00000001 do. 0.0
    elseif. y>SMC-0.00000001 do. SMC
    else. y end.
)
smo_take =: 4 : 0
    first =. x
    second =. y
    if. first=second do. 0 return. end.
    alpha1 =. first{SMAlpha
    alpha2 =. second{SMAlpha
    y1 =. first{SMY
    y2 =. second{SMY
    e1 =. first{SMError
    e2 =. second{SMError
    if. y1~:y2 do.
        lo =. 0.0>.alpha2-alpha1
        hi =. SMC<.(SMC+alpha2)-alpha1
    else.
        lo =. 0.0>.(alpha2+alpha1)-SMC
        hi =. SMC<.alpha2+alpha1
    end.
    if. lo=hi do. 0 return. end.
    k11 =. (<first,first){SMQ
    k12 =. (<first,second){SMQ
    k22 =. (<second,second){SMQ
    eta =. (k11+k22)-2*k12
    if. eta<:0 do. 0 return. end.
    a2 =. alpha2+(y2*(e1-e2))%eta
    clipping =. 0
    if. a2<lo do. a2 =. lo [ clipping =. 1
    elseif. a2>hi do. a2 =. hi [ clipping =. 2 end.
    a2 =. smo_snap a2
    if. (|a2-alpha2)<Epsilon*((a2+alpha2)+Epsilon) do. 0 return. end.
    a1 =. smo_snap alpha1+((y1*y2)*(alpha2-a2))
    t1 =. y1*(a1-alpha1)
    t2 =. y2*(a2-alpha2)
    b1 =. ((e1+t1*k11)+t2*k12)+SMB
    b2 =. ((e2+t1*k12)+t2*k22)+SMB
    if. (a1>0)*.a1<SMC do. threshold =. b1
    elseif. (a2>0)*.a2<SMC do. threshold =. b2
    else. threshold =. (b1+b2)%2 end.
    delta =. threshold-SMB
    for_i. i.#SMY do.
        adjustment =. ((t1*(<first,i){SMQ)+t2*(<second,i){SMQ)-delta
        SMError =: ((i{SMError)+adjustment)i}SMError
    end.
    if. (a1>0)*.a1<SMC do. SMError =: 0.0 first}SMError end.
    if. (a2>0)*.a2<SMC do. SMError =: 0.0 second}SMError end.
    SMAlpha =: a1 first}SMAlpha
    SMAlpha =: a2 second}SMAlpha
    SMB =: threshold
    smo_count 3
    smo_count 7+clipping
    1
)
smo_examine =: 3 : 0
    second =. y
    smo_count 2
    residual =. (second{SMError)*second{SMY
    violates =. ((residual < -Tolerance)*.SMC>second{SMAlpha)+.((residual>Tolerance)*.0<second{SMAlpha)
    if. -.violates do. 0 return. end.
    partner =. _1
    largest =. _1.0
    for_i. i.#SMY do.
        if. (i~:second)*.smo_nonbound i do.
            difference =. |(i{SMError)-second{SMError
            if. difference>largest do. partner =. i [ largest =. difference end.
        end.
    end.
    if. partner>:0 do.
        if. partner smo_take second do. smo_count 4
                1 return. end.
    end.
    for_i. i.#SMY do.
        if. smo_nonbound i do.
            if. i smo_take second do. smo_count 5
                1 return. end.
        end.
    end.
    for_i. i.#SMY do.
        if. i smo_take second do. smo_count 6
                1 return. end.
    end.
    0
)
smo_train =: 3 : 0
    'points labels kernel matrix coefficient' =. y
    SMX =: points
    SMY =: labels
    SMKernel =: kernel
    SMQ =: matrix
    SMC =: coefficient
    SMAlpha =: (#labels)$0.0
    SMError =: -0.0+labels
    SMB =: 0.0
    SMCounts =: 10$0
    SMRecords =: 0$a:
    converged =. 0
    all =. 1
    while. 1 do.
        examined =. 2{SMCounts
        changed =. 0
        for_i. i.#SMY do.
            if. all+.smo_nonbound i do. changed =. changed+smo_examine i end.
        end.
        smo_count -.all
        snapshot =. i.0
        if. all do. snapshot =. SMAlpha end.
        SMRecords =: SMRecords,<(<all),(<((2{SMCounts)-examined)),(<changed),<snapshot
        if. all*.changed=0 do.
            converged =. 1
            break.
        end.
        if. MaxPasses=#SMRecords do. break. end.
        if. all do. all =. 0
        elseif. changed=0 do. all =. 1 end.
    end.
    (<SMX),(<SMY),(<SMKernel),(<SMQ),(<SMC),(<SMAlpha),(<SMB),(<SMCounts),(<SMRecords),<converged
)
smo_decision =: 4 : 0
    points =. 0{::x
    labels =. 1{::x
    kernel =. 2{::x
    alpha =. 5{::x
    total =. 0.0
    for_i. I.alpha>0 do.
        term =. ((i{alpha)*i{labels)*(kernel kernel_value (<i{points),<y)
        total =. total+term
    end.
    total-6{::x
)
smo_decisions =: 4 : 0
    values =. i.0
    for_point. y do. values =. values,x smo_decision point end.
    values
)
smo_training_values =: 3 : 0
    labels =. 1{::y
    matrix =. 3{::y
    alpha =. 5{::y
    values =. i.0
    for_i. i.#labels do.
        total =. 0.0
        for_j. I.alpha>0 do. total =. total+((j{alpha)*j{labels)*(<i,j){matrix end.
        values =. values,total-6{::y
    end.
    values
)
