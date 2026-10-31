curve_lines =: 3 : 0
    'collections estimates width height time_limit' =. y
    cells =. (height,width)$' '
    for_group. i.#collections do.
        letter =. group{'ABCDEF'
        maximum =. >./2{"1 group{::collections
        previous =. _1
        for_column. i.width do.
            moment =. column*<.time_limit%width
            if. moment>maximum do.
                break.
            end.
            row =. (group{::estimates)row_at moment
            band =. (height-1)<.<.(4{row)*height
            last =. band>.previous-1
            for_vertical. band+i.(last-band)+1 do.
                cell =. (<vertical,column){cells
                if. (cell=' ')+.cell=letter do.
                    character =. letter
                else.
                    character =. '*'
                end.
                cells =. character (<vertical,column)}cells
            end.
            previous =. band
        end.
    end.
    border =. '   +',(width#'-'),'+'
    lines =. <border
    for_band. |.i.height do.
        label =. ":<.(100*band)%height
        lines =. lines,<((3-#label)#' '),label,'|',(band{cells),'|'
    end.
    lines,<border
)
