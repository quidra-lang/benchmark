Categories =: ;:'VFR MVFR IFR LIFR'
covers =: 4 : '((2{::x)<:y)*.((4{::x)<:hourmark y)*.(hourmark y)<5{::x'
chosen_forecast =: 4 : 0
    chosen =. NONE
    for_b. x do.
        f =. >b
        if. f covers y do.
            if. isnone chosen do. chosen =. f
            elseif. (2{::f)>:2{::chosen do. chosen =. f end.
        end.
    end.
    chosen
)
contingency =: 3 : '(<4 4$0x),<0x'
add_hit =: 4 : 0
    'expected observed hit' =. x
    'table temporaryhits' =. y
    row =. Categories i.<expected
    col =. Categories i.<observed
    index =. <row,col
    table =. (1+index{table) index}table
    (<table),<temporaryhits+hit
)
row_totals =: 3 : '+/"1 >{.y'
column_totals =: 3 : '+/> {.y'
total =: 3 : '+/ , >{.y'
hits =: 3 : 0
    table =. >{.y
    k =. 0x
    for_i. i.4 do. k =. k+(<i,i){table end.
    k,total y
)
hits_temporary =: 3 : '(1{::y),total y'
skill =: 3 : 0
    'k n' =. hits y
    e =. +/(row_totals y)*column_totals y
    ((n*k)-e),(n*n)-e
)
pod =: 4 : 0
    t =. >{.y
    ((<x,x){t),x{column_totals y
)
far =: 4 : 0
    t =. >{.y
    row =. x{row_totals y
    (row-(<x,x){t),row
)
