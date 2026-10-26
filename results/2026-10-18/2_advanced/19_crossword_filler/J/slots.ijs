starts_run =: 4 : 0
    step =. 1 0
    if. x do. step =. 0 1 end.
    (is_open y)*.-.is_open y-step
)
run_length =: 4 : 0
    step =. 1 0
    if. x do. step =. 0 1 end.
    length =. 0
    while. is_open y+length*step do. length =. length+1 end.
    length
)
find_short_run =: 3 : 0
    for_row. i.GridHeight do.
        for_column. i.GridWidth do.
            for_across. 1 0 do.
                if. across starts_run row,column do.
                    if. 2=across run_length row,column do.
                        direction =. 'down'
                        if. across do. direction =. 'across' end.
                        (<(row*GridWidth)+column),<direction return.
                    end.
                end.
            end.
        end.
    end.
    0$a:
)
build_layout =: 3 : 0
    NumberMap =: (#GridCells)$0
    AcrossOwner =: DownOwner =: (#GridCells)$_1
    SlotNumbers =: SlotAcross =: 0$0
    SlotCells =: SlotLabels =: SlotCrossings =: 0$a:
    next =. 0
    for_row. i.GridHeight do.
        for_column. i.GridWidth do.
            for_across. 1 0 do.
                if. -.across starts_run row,column do. continue. end.
                length =. across run_length row,column
                if. length<3 do. continue. end.
                start =. (row*GridWidth)+column
                if. 0=start{NumberMap do. next =. next+1
                    NumberMap =: next start}NumberMap end.
                index =. #SlotCells
                step =. GridWidth
                suffix =. 'D'
                if. across do. step =. 1
                    suffix =. 'A' end.
                cells =. start+step*i.length
                SlotNumbers =: SlotNumbers,start{NumberMap
                SlotAcross =: SlotAcross,across
                SlotCells =: SlotCells,<cells
                SlotLabels =: SlotLabels,<(number start{NumberMap),suffix
                if. across do. AcrossOwner =: index cells}AcrossOwner
                else. DownOwner =: index cells}DownOwner end.
            end.
        end.
    end.
    SlotCount =: #SlotCells
    SlotLengths =: #&>SlotCells
    for_slot. i.SlotCount do.
        owners =. AcrossOwner
        if. slot{SlotAcross do. owners =. DownOwner end.
        crossings =. (slot{::SlotCells){owners
        SlotCrossings =: SlotCrossings,</:~crossings#~crossings>:0
    end.
    i.0
)
owner_count =: 3 : '(0<:y{AcrossOwner)+0<:y{DownOwner'
orphan_cell =: 3 : 0
    for_cell. white_cells '' do. if. 0=owner_count cell do. cell return. end. end.
    _1
)
