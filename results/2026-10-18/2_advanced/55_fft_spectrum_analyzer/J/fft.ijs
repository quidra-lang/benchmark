Pi =: 3.141592653589793
rot =: 3 : '(2 o.y)j.-(1 o.y)'
pow2 =: 3 : 0
    result =. 1
    while. result<y do.
        result =. 2*result
    end.
    result
)
radix2 =: 4 : 0
    inverse =. x
    values =. 0j0+y
    count =. #values
    bits =. 0
    power =. count
    while. power>1 do.
        bits =. bits+1
        power =. <.power%2
    end.
    for_index. 1+i.count-1 do.
        reversed =. 0
        rest =. index
        for_bit. i.bits do.
            reversed =. (2*reversed)+2|rest
            rest =. <.rest%2
        end.
        if. index<reversed do.
            temporary =. index{values
            values =. (reversed{values)index}values
            values =. temporary reversed}values
        end.
    end.
    twiddle =. rot (((2.0*Pi)*i.<.count%2)%count)
    if. inverse do.
        twiddle =. +twiddle
    end.
    size =. 2
    while. size<:count do.
        stride =. <.count%size
        half =. <.size%2
        for_start. size*i.<.count%size do.
            for_j. i.half do.
                t =. ((j*stride){twiddle)*(start+j+half){values
                u =. (start+j){values
                values =. (u+t)(start+j)}values
                values =. (u-t)(start+j+half)}values
            end.
        end.
        size =. 2*size
    end.
    if. inverse do.
        values =. values%count
    end.
    values
)
bluestein =: 3 : 0
    count =. #y
    size =. pow2 (2*count)-1
    indices =. i.count
    chirp =. rot (Pi*((2*count)|indices*indices))%count
    a =. size$0j0
    b =. a
    for_k. i.count do.
        a =. ((k{y)*k{chirp)k}a
        b =. (+k{chirp)k}b
        if. k do.
            b =. (k{b)(size-k)}b
        end.
    end.
    product =. (0 radix2 a)*0 radix2 b
    convolution =. 1 radix2 product
    chirp*count{.convolution
)
dft =: 3 : 0
    if. (#y)=pow2 #y do.
        0 radix2 y
    else.
        bluestein y
    end.
)
idft =: 3 : 0
    if. (#y)=pow2 #y do.
        1 radix2 y
    else.
        (+bluestein +y)%#y
    end.
)
packed_real =: 3 : 0
    count =. #y
    half =. <.count%2
    even =. 2*i.half
    z =. (even{y)j.(even+1){y
    transformed =. 0 radix2 z
    result =. 0$0j0
    for_k. i.half+1 do.
        a =. (half|k){transformed
        b =. +(half|half-k){transformed
        e =. (a+b)%2.0
        o =. (a-b)%0j2
        result =. result,e+(rot ((2.0*Pi)*k)%count)*o
    end.
    result
)
convolution =: 4 : 0
    count =. (#x)+(#y)-1
    size =. pow2 count
    transformed =. (0 radix2 size{.x)*0 radix2 size{.y
    count{.9 o.1 radix2 transformed
)
chirp_z =: 4 : 0
    'sample_rate low high points' =. x
    count =. #y
    step =. (high-low)%(points-1)
    size =. pow2 count+points-1
    a =. size$0j0
    b =. a
    for_n. i.count do.
        first =. rot ((((2.0*Pi)*low)*n)%sample_rate)
        second =. rot (((Pi*step)*n)*n)%sample_rate
        a =. (((n{y)*first)*second)n}a
    end.
    for_offset. (1-count)+i.count+points-1 do.
        value =. +rot ((((Pi*step)*offset)*offset)%sample_rate)
        b =. value (size|offset)}b
    end.
    product =. (0 radix2 a)*0 radix2 b
    g =. 1 radix2 product
    result =. 0$0j0
    for_j. i.points do.
        result =. result,(rot ((((Pi*step)*j)*j)%sample_rate))*j{g
    end.
    result
)
