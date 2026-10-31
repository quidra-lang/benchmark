WindowNames =: ;:'rectangular hann hamming blackman flattop'
window =: 4 : 0
    coefficients =. (WindowNames i.<x){::(<1.0),(<0.5 0.5),(<0.54 0.46),(<0.42 0.5 0.08),<0.21557895 0.41663158 0.277263158 0.083578947 0.006947368
    result =. i.0
    for_n. i.y do.
        total =. 0.0
        for_j. i.#coefficients do.
            sign =. _1^j
            cosine =. 2 o.((((2.0*Pi)*j)*n)%y)
            total =. total+(sign*j{coefficients)*cosine
        end.
        result =. result,total
    end.
    result
)
window_figures =: 4 : 0
    s1 =. 0.0
    s2 =. 0.0
    scalloping =. 0j0
    for_n. i.#y do.
        value =. n{y
        s1 =. s1+value
        s2 =. s2+value*value
        scalloping =. scalloping+value*rot (Pi*n)%#y
    end.
    enbw =. ((#y)*s2)%(s1*s1)
    scalloping_db =. (-20.0*^. (|scalloping)%s1)%2.302585092994046
    s1,s2,(s1%#y),enbw,((enbw*x)%#y),scalloping_db
)
