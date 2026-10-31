e_values =: 0&{::
e_vectors =: 1&{::
e_sweeps =: 2&{::
off_diagonal =: 3 : 0
    result =. 0.0
    for_p. i.(#y)-1 do.
        for_q. (p+1)+i.(#y)-p+1 do.
            value =. (<p,q){y
            result =. result+value*value
        end.
    end.
    result
)
jacobi_rotate =: 3 : 0
    'a vectors p q' =. y
    off =. (<p,q){a
    if. off=0.0 do.
        (<a),<vectors return.
    end.
    theta =. (((<q,q){a)-(<p,p){a)%(2.0*off)
    t =. 1.0%((|theta)+%:(theta*theta)+1.0)
    if. theta<0 do.
        t =. -t
    end.
    c =. 1.0%%:(t*t)+1.0
    s =. t*c
    for_r. i.#a do.
        if. (r=p)+.r=q do.
            continue.
        end.
        rp =. (<r,p){a
        rq =. (<r,q){a
        first =. (c*rp)-s*rq
        second =. (s*rp)+c*rq
        a =. first (<r,p)}a
        a =. first (<p,r)}a
        a =. second (<r,q)}a
        a =. second (<q,r)}a
    end.
    a =. (((<p,p){a)-t*off)(<p,p)}a
    a =. (((<q,q){a)+t*off)(<q,q)}a
    a =. 0.0 (<p,q)}a
    a =. 0.0 (<q,p)}a
    for_r. i.#vectors do.
        rp =. (<r,p){vectors
        rq =. (<r,q){vectors
        vectors =. ((c*rp)-s*rq)(<r,p)}vectors
        vectors =. ((s*rp)+c*rq)(<r,q)}vectors
    end.
    (<a),<vectors
)
jacobi =: 3 : 0
    a =. copy_matrix y
    vectors =. 0.0+identity #y
    initial =. off_diagonal a
    count =. 0
    if. initial>0 do.
        for_sweep. 1+i.100 do.
            for_p. i.(#y)-1 do.
                for_q. (p+1)+i.(#y)-p+1 do.
                    'a vectors' =. jacobi_rotate (<a),(<vectors),(<p),<q
                end.
            end.
            remaining =. off_diagonal a
            if. (count=0)*.remaining<1e_16*initial do.
                count =. sweep
            end.
            if. remaining<1e_22*initial do.
                break.
            end.
        end.
    end.
    diagonal =. i.0
    for_index. i.#y do.
        diagonal =. diagonal,(<index,index){a
    end.
    order =. /:(-diagonal),.i.#y
    eigenvalues =. order{diagonal
    eigenvectors =. (0,#y)$0.0
    for_index. order do.
        eigenvectors =. eigenvectors,orient normalize vectors column index
    end.
    (<eigenvalues),(<eigenvectors),<count
)
power_iteration =: 3 : 0
    'values reference' =. y
    work =. copy_matrix values
    result =. 0$a:
    for_k. i.#values do.
        x =. (#values)$1.0
        agreement =. _1
        vector_reference =. k{e_vectors reference
        opposite =. -vector_reference
        for_iteration. 1+i.1000 do.
            x =. normalize work product x
            difference =. (x maximum_difference vector_reference)<.x maximum_difference opposite
            if. (agreement<0)*.difference<0.000001 do.
                agreement =. iteration
            end.
        end.
        w =. work product x
        value =. x dot w
        vector =. orient normalize x
        matched =. ((|value-k{e_values reference)<:1e_8*0{e_values reference)*.(vector maximum_difference vector_reference)<:0.000001
        result =. result,<(<value),(<vector),(<agreement),<matched
        work =. deflate (<work),(<value),<vector
    end.
    result
)
