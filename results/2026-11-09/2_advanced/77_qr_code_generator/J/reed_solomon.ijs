xor =: 22 b.
gf_initialize =: 3 : 0
    GFExp =: 255$1
    for_i. 1+i.254 do.
        doubled =. 2*(i-1){GFExp
        if. doubled>:256 do.
            doubled =. doubled xor 285
        end.
        GFExp =: doubled i}GFExp
    end.
    GFLog =: (i.255)GFExp}256$0
)
gf_multiply =: 4 : 0
    if. (x=0)+.y=0 do.
        0 return.
    end.
    (255|((x{GFLog)+y{GFLog)){GFExp
)
gf_divide =: 4 : 0
    if. x=0 do.
        0 return.
    end.
    (255|255+(x{GFLog)-y{GFLog){GFExp
)
generator =: 3 : 0
    coefficients =. ,1
    for_exponent. i.y do.
        product =. (1+#coefficients)$0
        for_i. i.#coefficients do.
            coefficient =. i{coefficients
            product =. ((i{product)xor coefficient)i}product
            value =. ((i+1){product)xor coefficient gf_multiply exponent{GFExp
            product =. value(i+1)}product
        end.
        coefficients =. product
    end.
    coefficients
)
parity =: 4 : 0
    polynomial =. generator x
    remainder =. y,x$0
    for_i. i.#y do.
        leading =. i{remainder
        if. leading do.
            for_j. i.#polynomial do.
                value =. ((i+j){remainder)xor leading gf_multiply j{polynomial
                remainder =. value(i+j)}remainder
            end.
        end.
    end.
    (-x){.remainder
)
syndromes =: 4 : 0
    values =. i.0
    for_exponent. i.x do.
        value =. 0
        for_word. y do.
            value =. (value gf_multiply exponent{GFExp)xor word
        end.
        values =. values,value
    end.
    values
)
polynomial_value =: 4 : 0
    value =. 0
    for_coefficient. |.x do.
        value =. (value gf_multiply y)xor coefficient
    end.
    value
)
correct =: 4 : 0
    degree =. x
    received =. y
    original =. degree syndromes received
    if. -. +./original do.
        (<original),(<received),(<i.0),<1 return.
    end.
    locator =. 1,degree$0
    previous =. locator
    length =. 0
    shift =. 1
    beta =. 1
    for_step. i.degree do.
        discrepancy =. step{original
        for_i. 1+i.length do.
            discrepancy =. discrepancy xor (i{locator)gf_multiply(step-i){original
        end.
        if. discrepancy=0 do.
            shift =. shift+1
            continue.
        end.
        saved =. locator
        multiplier =. discrepancy gf_divide beta
        for_i. i.1+degree-shift do.
            value =. ((i+shift){locator)xor multiplier gf_multiply i{previous
            locator =. value(i+shift)}locator
        end.
        if. (2*length)<:step do.
            length =. 1+step-length
            previous =. saved
            beta =. discrepancy
            shift =. 1
        else.
            shift =. shift+1
        end.
    end.
    failure =. (<original),(<i.0),(<i.0),<0
    if. length>degree intdiv 2 do.
        failure return.
    end.
    locator =. (1+length){.locator
    positions =. i.0
    count =. #received
    for_i. i.count do.
        inverse =. (255|255-((count-1)-i)){GFExp
        if. 0=locator polynomial_value inverse do.
            positions =. positions,i
        end.
    end.
    if. length~:#positions do.
        failure return.
    end.
    omega =. degree$0
    for_i. i.degree do.
        for_j. i.1+length<.(degree-1)-i do.
            value =. ((i+j){omega)xor(i{original)gf_multiply j{locator
            omega =. value(i+j)}omega
        end.
    end.
    derivative =. length$0
    for_exponent. 1+2*i.(1+length)intdiv 2 do.
        derivative =. (exponent{locator)(exponent-1)}derivative
    end.
    corrected =. received
    for_i. positions do.
        location =. (255|(count-1)-i){GFExp
        inverse =. (255|255-((count-1)-i)){GFExp
        denominator =. derivative polynomial_value inverse
        if. denominator=0 do.
            failure return.
        end.
        magnitude =. location gf_multiply(omega polynomial_value inverse)gf_divide denominator
        corrected =. ((i{corrected)xor magnitude)i}corrected
    end.
    if. +./degree syndromes corrected do.
        failure return.
    end.
    changed =. I.corrected~:received
    (<original),(<corrected),(<changed),<1
)
