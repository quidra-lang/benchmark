polynomial_remainder =: 4 : 0
    value =. y
    divisor =. x
    d =. divisor
    divisor_degree =. _1
    while. d do.
        divisor_degree =. divisor_degree+1
        d =. d intdiv 2
    end.
    while. value>:2^divisor_degree do.
        degree =. _1
        d =. value
        while. d do.
            degree =. degree+1
            d =. d intdiv 2
        end.
        value =. value xor divisor*2^degree-divisor_degree
    end.
    value
)
format_information =: 4 : 0
    indicator =. (Levels i.<x){1 0 3 2
    shifted =. 1024*(8*indicator)+y
    (shifted+1335 polynomial_remainder shifted)xor 21522
)
version_information =: 3 : 0
    shifted =. 4096*y
    shifted+7973 polynomial_remainder shifted
)
format_positions =: 3 : 0
    first =. (8+y*i.6),(8+7*y),(8+8*y),(7+8*y),(14-9+i.6)+8*y
    second =. ((y-1)-i.8)+8*y
    second =. second,8+y*(y-15)+8+i.7
    (<first),<second
)
version_positions =: 3 : 0
    indices =. i.18
    first =. ((y-11)+3|indices)+y*(indices intdiv 3)
    second =. (indices intdiv 3)+y*(y-11)+3|indices
    (<first),<second
)
write_value =: 4 : 0
    'positions value' =. x
    bits =. |.(#positions)write_bits value
    bits positions}y
)
read_value =: 4 : '+/(x{y)*2^i.#x'
function_matrix =: 4 : 0
    version =. x
    alignments =. y
    n =. 17+4*version
    symbol =. (n*n)$0
    areas =. symbol
    for_center. 3 2$3,3,(n-4),3,3,n-4 do.
        'cx cy' =. center
        for_dy. _4+i.9 do.
            for_dx. _4+i.9 do.
                xx =. cx+dx
                yy =. cy+dy
                if. (xx>:0)*.(xx<n)*.(yy>:0)*.yy<n do.
                    position =. xx+n*yy
                    symbol =. ((>./|dx,dy)e.0 1 3)position}symbol
                    areas =. 1 position}areas
                end.
            end.
        end.
    end.
    for_i. 8+i.n-16 do.
        positions =. (6+n*i),i+6*n
        symbol =. (0=2|i)positions}symbol
        areas =. 1 positions}areas
    end.
    if. #alignments do.
        first =. {.alignments
        last =. {:alignments
        for_cy. alignments do.
            for_cx. alignments do.
                if. ((cx=first)*.cy=first)+.((cx=first)*.cy=last)+.((cx=last)*.cy=first) do.
                    continue.
                end.
                for_dy. _2+i.5 do.
                    for_dx. _2+i.5 do.
                        position =. (cx+dx)+n*cy+dy
                        symbol =. (1~:>./|dx,dy)position}symbol
                        areas =. 1 position}areas
                    end.
                end.
            end.
        end.
    end.
    position =. 8+n*n-8
    symbol =. 1 position}symbol
    areas =. 1 position}areas
    for_positions. format_positions n do.
        positions =. >positions
        areas =. 2 positions}areas
        symbol =. 0 positions}symbol
    end.
    if. version>:7 do.
        for_positions. version_positions n do.
            positions =. >positions
            areas =. 3 positions}areas
            symbol =. (positions;version_information version)write_value symbol
        end.
    end.
    order =. i.0
    rights =. (n-1)-2*i.(n-7)intdiv 2
    rights =. rights,5 3 1
    for_pair. i.#rights do.
        rows =. i.n
        if. 0=2|pair do.
            rows =. |.rows
        end.
        right =. pair{rights
        for_yy. rows do.
            for_xx. right,right-1 do.
                position =. xx+n*yy
                if. 0=position{areas do.
                    order =. order,position
                end.
            end.
        end.
    end.
    (<n),(<symbol),(<areas),<order
)
