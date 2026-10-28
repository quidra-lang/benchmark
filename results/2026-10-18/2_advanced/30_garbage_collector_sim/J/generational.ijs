old_blocks =: 3 : 'free_blocks Young,HeapSize'
write_barrier =: 3 : 0
    'target value' =. y
    index =. target-1
    if. (index{ObjAddr)<Young do.
        i.0 return.
    end.
    Barriers =: Barriers+1
    if. value>0 do.
        if. (((value-1){ObjAddr)<Young)*.-.index{ObjRemembered do.
            ObjRemembered =: 1 index}ObjRemembered
            Remembers =: Remembers+1
        end.
    end.
    i.0
)
evacuate =: 3 : 0
    if. y=0 do.
        1 return.
    end.
    ident =. y-1
    if. -.ident{Pending do.
        1 return.
    end.
    Pending =: 0 ident}Pending
    ObjAge =: (>:(ident{ObjAge))ident}ObjAge
    ObjMoves =: (>:(ident{ObjMoves))ident}ObjMoves
    kind =. 3{::CurrentRecord
    tenuring =. (<kind)e.'tenure';'full'
    if. tenuring+.(ident{ObjAge)>:PromotionAge do.
        address =. (old_blocks 0)first_fit ident{ObjSize
        if. address<0 do.
            0 return.
        end.
        ObjAddr =: address ident}ObjAddr
        7 record_add ident
    else.
        ObjAddr =: Target ident}ObjAddr
        Target =: Target+ident{ObjSize
    end.
    6 record_add ident
    if. (<kind)e.'minor';'tenure' do.
        4 record_add ident
    end.
    EvacuationQueue =: EvacuationQueue,ident
    1
)
evacuate_fields =: 3 : 0
    for_child. y do.
        if. -.evacuate child do.
            0 return.
        end.
    end.
    1
)
collect_generation =: 3 : 0
    'line request kind' =. y
    new_record y
    if. (<kind)e.'major';'full' do.
        mark_objects Roots
        for_ident. I.ObjPresent*.ObjAddr>:Young do.
            record_work 1
            if. -.ident{ObjMarked do.
                5 record_add ident
                ObjPresent =: 0 ident}ObjPresent
                ObjRemembered =: 0 ident}ObjRemembered
            end.
        end.
    end.
    Pending =: ObjPresent*.ObjAddr<Young
    destination =. Half-Base
    Target =: destination
    EvacuationQueue =: i.0
    record_work #Roots
    for_root. Roots do.
        if. -.evacuate root do.
            0 return.
        end.
    end.
    remembered =. I.ObjRemembered
    remembered =. (/:remembered{ObjAddr){remembered
    for_ident. remembered do.
        fields =. ident{::ObjFields
        record_work 1+#fields
        if. -.evacuate_fields fields do.
            0 return.
        end.
    end.
    position =. 0
    while. position<#EvacuationQueue do.
        ident =. position{EvacuationQueue
        position =. position+1
        fields =. ident{::ObjFields
        record_work (ident{ObjSize)+#fields
        if. -.evacuate_fields fields do.
            0 return.
        end.
    end.
    for_ident. I.Pending do.
        5 record_add ident
        ObjPresent =: 0 ident}ObjPresent
    end.
    Base =: destination
    Top =: Target
    ObjRemembered =: (#ObjSize)$0
    for_ident. I.ObjPresent*.ObjAddr>:Young do.
        for_child. ident{::ObjFields do.
            if. child>0 do.
                if. ((child-1){ObjAddr)<Young do.
                    ObjRemembered =: 1 ident}ObjRemembered
                    break.
                end.
            end.
        end.
    end.
    finish_record 0
    1
)
allocate_generation =: 3 : 0
    'line request' =. y
    for_attempt. i.3 do.
        if. (Top+request)<:Base+Half do.
            address =. Top
            Top =: Top+request
            address return.
        end.
        if. attempt=2 do.
            _1 return.
        end.
        scarce =. (largest_free old_blocks 0)<Top-Base
        if. attempt=0 do.
            kind =. 'minor'
            if. scarce do.
                kind =. 'major'
            end.
        else.
            kind =. 'tenure'
            if. scarce do.
                kind =. 'full'
            end.
        end.
        if. -.collect_generation (<line),(<request),<kind do.
            _1 return.
        end.
    end.
    _1
)
