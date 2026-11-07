copy_object =: 3 : 0
    if. y=0 do.
        i.0 return.
    end.
    ident =. y-1
    if. ident{Copied do.
        i.0 return.
    end.
    Copied =: 1 ident}Copied
    ObjAddr =: Top ident}ObjAddr
    Top =: Top+ident{ObjSize
    ObjMoves =: (>:(ident{ObjMoves))ident}ObjMoves
    4 record_add ident
    6 record_add ident
    CopyQueue =: CopyQueue,ident
    i.0
)
collect_copy =: 3 : 0
    'line request' =. y
    new_record (<line),(<request),<'copy'
    Base =: Half-Base
    Top =: Base
    Copied =: (#ObjSize)$0
    CopyQueue =: i.0
    record_work #Roots
    for_root. Roots do.
        copy_object root
    end.
    position =. 0
    while. position<#CopyQueue do.
        ident =. position{CopyQueue
        position =. position+1
        fields =. ident{::ObjFields
        record_work (ident{ObjSize)+#fields
        for_child. fields do.
            copy_object child
        end.
    end.
    for_ident. I.ObjPresent*.-.Copied do.
        5 record_add ident
        ObjPresent =: 0 ident}ObjPresent
    end.
    finish_record 0
)
