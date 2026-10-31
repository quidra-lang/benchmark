doc_kind =: 3 : '0{::y{::Documents'
doc_value =: 3 : '1{::y{::Documents'
doc_children =: 3 : '2{::y{::Documents'
doc_create =: 4 : 0
    'value children forced' =. y
    number =. #Documents
    record =. (<x),(<value),(<children),(<forced),<'break'
    Documents =: Documents,<record
    number
)
doc_text =: 3 : '''text''doc_create(<,y),(<i.0),<0'
doc_suffix =: 3 : '''suffix''doc_create(<y),(<i.0),<0'
doc_if_break =: 3 : '''if_break''doc_create(<y),(<i.0),<0'
doc_symbol =: 3 : 'y doc_create(<''''),(<i.0),<0'
doc_concat =: 3 : 0
    pending =. |.y
    result =. i.0
    while. #pending do.
        number =. {:pending
        pending =. }:pending
        kind =. doc_kind number
        if. kind-:'concat' do.
            pending =. pending,|.doc_children number
        elseif. kind-:'text' do.
            value =. doc_value number
            if. 0=#value do. continue. end.
            if. #result do.
                previous =. {:result
                if. 'text'-:doc_kind previous do.
                    result =. }:result
                    number =. doc_text(doc_value previous),value
                end.
            end.
            result =. result,number
        else.
            result =. result,number
        end.
    end.
    if. 0=#result do. doc_text '' return. end.
    if. 1=#result do. {.result return. end.
    'concat'doc_create(<''),(<result),<0
)
doc_forced =: 3 : 0
    if. (<doc_kind y)e.'hardline';'break_parent' do. 1 return. end.
    for_child. doc_children y do.
        if. doc_forced child do. 1 return. end.
    end.
    0
)
doc_group =: 3 : 0
    child =. doc_concat y
    'group'doc_create(<''),(<,child),<doc_forced child
)
doc_nest =: 4 : 0
    'nest'doc_create(<x),(<,doc_concat y),<0
)
doc_align =: 3 : 0
    'align'doc_create(<''),(<,doc_concat y),<0
)
doc_groups =: 3 : 0
    result =. i.0
    if. 'group'-:doc_kind y do. result =. ,y end.
    for_child. doc_children y do.
        result =. result,doc_groups child
    end.
    result
)
initialize_documents =: 3 : 0
    Documents =: 0$a:
    EmptyDoc =: doc_text ''
    LineDoc =: doc_symbol 'line'
    SoftLineDoc =: doc_symbol 'softline'
    HardLineDoc =: doc_symbol 'hardline'
    BreakParentDoc =: doc_symbol 'break_parent'
)
