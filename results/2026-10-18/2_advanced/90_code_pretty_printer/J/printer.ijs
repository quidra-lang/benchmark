fit_document =: 3 : 0
    'remaining first rest' =. y
    if. remaining<0 do. 0 return. end.
    check =. ,:first
    next =. (#rest)-1
    while. 1 do.
        if. 0=#check do.
            if. next<0 do. 1 return. end.
            check =. ,:next{rest
            next =. next-1
        end.
        'indent mode number' =. _1{check
        check =. }:check
        'kind value children forced recorded' =. number{::Documents
        select. kind
        case. 'text' do. remaining =. remaining-#value
        case. 'if_break' do.
            remaining =. remaining-#(mode=0){::value
        case. 'line' do.
            if. mode do. 1 return. end.
            remaining =. remaining-1
        case. 'softline' do.
            if. mode do. 1 return. end.
        case. 'hardline' do. 1 return.
        case. 'concat' do.
            for_child. |.children do. check =. check,indent,mode,child end.
        case. 'group' do.
            check =. check,indent,(mode+.forced),{.children
        case. 'nest';'align' do.
            check =. check,indent,mode,{.children
        end.
        if. remaining<0 do. 0 return. end.
    end.
)
finalize_line =: 3 : 0
    output =. trim_spaces PrintCurrent
    if. #PrintPending do.
        suffix =. ' 'join PrintPending
        column =. profile 'comment_column'
        if. (column>0)*.((#output)<column-1)*.((column-1)+#suffix)<:profile 'width' do.
            output =. output,(((column-1)-#output)$' '),suffix
        else.
            output =. output,' ',suffix
        end.
    end.
    PrintLines =: PrintLines,<output
    PrintPending =: 0$a:
)
layout_document =: 3 : 0
    PrintLines =: PrintPending =: 0$a:
    PrintCurrent =: ''
    stack =. ,:0,1,y
    while. #stack do.
        'indent mode number' =. _1{stack
        stack =. }:stack
        'kind value children forced recorded' =. number{::Documents
        select. kind
        case. 'text' do. PrintCurrent =: PrintCurrent,value
        case. 'if_break' do. PrintCurrent =: PrintCurrent,(mode=0){::value
        case. 'line';'softline';'hardline' do.
            if. (kind-:'hardline')+.mode do.
                finalize_line ''
                PrintCurrent =: indent$' '
            elseif. kind-:'line' do.
                PrintCurrent =: PrintCurrent,' '
            end.
        case. 'concat' do.
            for_child. |.children do. stack =. stack,indent,mode,child end.
        case. 'nest' do. stack =. stack,(indent+value),mode,{.children
        case. 'align' do. stack =. stack,(#PrintCurrent),mode,{.children
        case. 'suffix' do. PrintPending =: PrintPending,<value
        case. 'group' do.
            child_mode =. 0
            recorded =. 'flat'
            if. mode do.
                if. forced do.
                    recorded =. 'forced'
                    child_mode =. 1
                else.
                    remaining =. (profile 'width')-#PrintCurrent
                    candidate =. indent,0,{.children
                    if. -.fit_document(<remaining),(<candidate),<stack do.
                        recorded =. 'break'
                        child_mode =. 1
                    end.
                end.
            end.
            record =. number{::Documents
            Documents =: (<(<recorded)4}record)number}Documents
            stack =. stack,indent,child_mode,{.children
        end.
    end.
    finalize_line ''
    PrintLines
)
