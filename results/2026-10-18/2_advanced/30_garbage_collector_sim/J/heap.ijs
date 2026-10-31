reset_heap =: 3 : 0
    ObjSize =: ObjAddr =: ObjMoves =: ObjAge =: ObjRC =: i.0
    ObjPresent =: ObjMarked =: ObjRemembered =: i.0
    ObjFields =: Records =: 0$a:
    Base =: Top =: Target =: Barriers =: Remembers =: 0
    i.0
)
add_object =: 3 : 0
    'pointers data address' =. y
    ObjSize =: ObjSize,1+pointers+data
    ObjAddr =: ObjAddr,address
    ObjFields =: ObjFields,<pointers$0
    ObjPresent =: ObjPresent,1
    ObjMarked =: ObjMarked,0
    ObjMoves =: ObjMoves,0
    ObjAge =: ObjAge,0
    ObjRC =: ObjRC,0
    ObjRemembered =: ObjRemembered,0
    #ObjSize
)
pair_of =: 3 : '(#y),+/y{ObjSize'
free_blocks =: 3 : 0
    'start finish' =. y
    ids =. I.ObjPresent*.(ObjAddr>:start)*.ObjAddr<finish
    ids =. (/:ids{ObjAddr){ids
    blocks =. 0 2$0
    position =. start
    for_ident. ids do.
        address =. ident{ObjAddr
        if. address>position do.
            blocks =. blocks,position,address-position
        end.
        position =. address+ident{ObjSize
    end.
    if. position<finish do.
        blocks =. blocks,position,finish-position
    end.
    blocks
)
free_list =: 3 : 0
    if. HeapKind-:'MARK_COMPACT' do.
        if. Top<HeapSize do.
            1 2$Top,HeapSize-Top
        else.
            0 2$0
        end.
        return.
    end.
    if. (<HeapKind)e.'COPYING';'GENERATIONAL' do.
        blocks =. 0 2$0
        if. Top<Base+Half do.
            blocks =. blocks,Top,(Base+Half)-Top
        end.
        if. HeapKind-:'GENERATIONAL' do.
            blocks =. blocks,free_blocks Young,HeapSize
        end.
        blocks return.
    end.
    free_blocks 0,HeapSize
)
first_fit =: 4 : 0
    for_block. x do.
        if. y<:1{block do.
            0{block return.
        end.
    end.
    _1
)
total_free =: 3 : '+/1{"1 y'
largest_free =: 3 : 0
    if. #y do.
        >./1{"1 y
    else.
        0
    end.
)
new_record =: 3 : 0
    'line request kind' =. y
    before =. (total_free free_list 0),largest_free free_list 0
    CurrentRecord =: (<1+#Records),(<line),(<request),(<kind),(<0 0),(<0 0),(<0 0),(<0 0),(<0),(<0),(<before),<0 0
    i.0
)
record_add =: 4 : 0
    pair =. x{::CurrentRecord
    CurrentRecord =: (<pair+1,y{ObjSize)x}CurrentRecord
)
record_work =: 3 : 'CurrentRecord =: (<y+9{::CurrentRecord)9}CurrentRecord'
finish_record =: 3 : 0
    blocks =. free_list 0
    CurrentRecord =: (<(total_free blocks),largest_free blocks)11}CurrentRecord
    Records =: Records,<CurrentRecord
    i.0
)
dec2 =: 4 : 0
    rounded =. ((200*x)+y)intdiv 2*y
    (":rounded intdiv 100),'.',_2{.'00',":100|rounded
)
pct =: 4 : 0
    if. y=0 do.
        '-'
    else.
        (100*x)dec2 y
    end.
)
class_table =: 3 : 0
    counts =. 5$0
    for_value. y do.
        index =. +/value>1 3 7 15
        counts =. (>:(index{counts))index}counts
    end.
    labels =. '1';'2-3';'4-7';'8-15';'16+'
    parts =. 0$a:
    for_index. i.5 do.
        parts =. parts,<(index{::labels),':',text index{counts
    end.
    ' 'join parts
)
heap_map =: 3 : 0
    cells =. HeapSize$'.'
    if. (<HeapKind)e.'COPYING';'GENERATIONAL' do.
        addresses =. (Half-Base)+i.Half
        cells =. '-'addresses}cells
    end.
    for_ident. I.ObjPresent do.
        address =. ident{ObjAddr
        letter =. 26|ident
        header =. '#'
        body =. '='
        if. ident{y do.
            header =. letter{'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
            body =. letter{'abcdefghijklmnopqrstuvwxyz'
        end.
        cells =. header address}cells
        positions =. (address+1)+i.(ident{ObjSize)-1
        cells =. body positions}cells
    end.
    cells
)
