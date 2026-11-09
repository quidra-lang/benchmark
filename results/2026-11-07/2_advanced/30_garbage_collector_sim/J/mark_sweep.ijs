push_mark =: 3 : 0
    ObjMarked =: 1 y}ObjMarked
    MarkStack =: MarkStack,y
    maximum =. (8{::CurrentRecord)>.#MarkStack
    CurrentRecord =: (<maximum)8}CurrentRecord
)
mark_objects =: 3 : 0
    ObjMarked =: 0(I.ObjPresent)}ObjMarked
    record_work #y
    MarkStack =: i.0
    for_root. y do.
        if. root=0 do.
            continue.
        end.
        ident =. root-1
        if. ident{ObjMarked do.
            continue.
        end.
        push_mark ident
        while. #MarkStack do.
            ident =. {:MarkStack
            MarkStack =: }:MarkStack
            4 record_add ident
            fields =. ident{::ObjFields
            record_work 1+#fields
            for_child. fields do.
                if. child>0 do.
                    child_index =. child-1
                    if. -.child_index{ObjMarked do.
                        push_mark child_index
                    end.
                end.
            end.
        end.
    end.
    i.0
)
sweep_objects =: 3 : 0
    record_work +/ObjPresent
    for_ident. I.ObjPresent*.-.ObjMarked do.
        5 record_add ident
        ObjPresent =: 0 ident}ObjPresent
    end.
    i.0
)
collect_mark =: 3 : 0
    'line request' =. y
    compact =. HeapKind-:'MARK_COMPACT'
    kind =. 'sweep'
    if. compact do.
        kind =. 'compact'
    end.
    new_record (<line),(<request),<kind
    mark_objects Roots
    if. -.compact do.
        sweep_objects 0
    else.
        ids =. I.ObjPresent
        ids =. (/:ids{ObjAddr){ids
        record_work (#ids)+#Roots
        destination =. 0
        for_ident. ids do.
            if. -.ident{ObjMarked do.
                5 record_add ident
                ObjPresent =: 0 ident}ObjPresent
                continue.
            end.
            record_work #ident{::ObjFields
            if. destination~:ident{ObjAddr do.
                6 record_add ident
                record_work ident{ObjSize
                ObjAddr =: destination ident}ObjAddr
                ObjMoves =: (>:(ident{ObjMoves))ident}ObjMoves
            end.
            destination =. destination+ident{ObjSize
        end.
        Top =: destination
    end.
    finish_record 0
)
