Unknown =: 0
Filled =: 1
Empty =: 2
fit_table =: 4 : 0
    cells =. x
    clue =. y
    n =. #cells
    m =. #clue
    empties =. 0,+/\cells=Empty
    table =. 1 (<0 0)}((n+1),m+1)$0
    for_end. 1+i.n do.
        for_count. i.m+1 do.
            fits =. (((end-1){cells)~:Filled)*.(<(end-1),count){table
            if. (-.fits)*.count>0 do.
                start =. end-(count-1){clue
                if. start>:0 do.
                    if. (end{empties)=start{empties do.
                        if. start=0 do. fits =. count=1
                        else. fits =. (((start-1){cells)~:Filled)*.(<(start-1),count-1){table end.
                    end.
                end.
            end.
            table =. fits (<end,count)}table
        end.
    end.
    table
)
has_placement =: 4 : '(<(#x),#y){x fit_table y'
solve_line =: 3 : 0
    'cells clue precise' =. y
    n =. #cells
    m =. #clue
    before =. cells fit_table clue
    if. -. (<n,m){before do. _1 return. end.
    after =. (|.cells) fit_table |.clue
    fillable =. covered =. n$0
    solved =. cells
    for_block. i.m do.
        size =. block{clue
        starts =. 0$0
        for_start. i.1+n-size do.
            end =. start+size
            if. Empty e.size{.start}.cells do. continue. end.
            if. start=0 do. left =. block=0
            else. left =. (((start-1){cells)~:Filled)*.(<(start-1),block){before end.
            if. end=n do. right =. block=m-1
            else. right =. ((end{cells)~:Filled)*.(<((n-end)-1),(m-block)-1){after end.
            if. left*.right do. starts =. starts,start end.
        end.
        if. precise do.
            for_start. starts do. fillable =. 1 (start+i.size)}fillable end.
        else.
            low =. {.starts
            high =. {:starts
            if. high<low+size do.
                indices =. high+i.(low+size)-high
                indices =. indices#~Unknown=indices{cells
                solved =. Filled indices}solved
            end.
            covered =. 1 (low+i.(high+size)-low)}covered
        end.
    end.
    for_index. I.cells=Unknown do.
        if. precise do.
            emptiable =. 0
            for_blocks. i.m+1 do.
                if. ((<index,blocks){before)*.(<((n-index)-1),m-blocks){after do. emptiable =. 1 break. end.
            end.
            if. (index{fillable)*.-.emptiable do. solved =. Filled index}solved
            elseif. emptiable*.-.index{fillable do. solved =. Empty index}solved end.
        elseif. -.index{covered do. solved =. Empty index}solved end.
    end.
    solved
)
