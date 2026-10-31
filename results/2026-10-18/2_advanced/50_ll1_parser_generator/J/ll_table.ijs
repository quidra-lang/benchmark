number_productions =: 3 : 0
    'order rules start' =. y
    result =. 0$a:
    for_lhs. i.#order do.
        for_rhs. lhs{::rules do.
            rhs =. >rhs
            number =. 1+#result
            notation =. (lhs{::order)production_text rhs
            result =. result,<(<number),(<lhs),(<rhs),<notation
        end.
    end.
    result
)
build_table =: 4 : 0
    'order rules start' =. x
    'nullable first follow passes terminals' =. y
    productions =. number_productions x
    columns =. terminals,<'$'
    predict =. 0$a:
    reasons =. 0$a:
    cells =. ((#order),#columns)$<i.0
    choices =. ((#order),#columns)$0
    for_production. productions do.
        'number lhs rhs notation' =. >production
        'values empty' =. ((<order),(<nullable),<first)first_sequence rhs
        original =. values
        if. empty do.
            values =. ~.values,lhs{::follow
        end.
        values =. terminal_order values
        token_reasons =. 0$a:
        for_token. values do.
            reason =. 'FOLLOW'
            if. token e.original do.
                reason =. 'FIRST'
            end.
            token_reasons =. token_reasons,<reason
            column =. columns i.token
            cell =. >(<lhs,column){cells
            cells =. (<cell,number)(<lhs,column)}cells
        end.
        predict =. predict,<values
        reasons =. reasons,<token_reasons
    end.
    conflicts =. 0$a:
    for_lhs. i.#order do.
        for_column. i.#columns do.
            numbers =. >(<lhs,column){cells
            if. 0=#numbers do.
                continue.
            end.
            chosen =. {.numbers
            has_first =. 0
            has_follow =. 0
            for_number. numbers do.
                index =. ((number-1){::predict)i.column{columns
                reason =. index{::(number-1){::reasons
                if. reason-:'FIRST' do.
                    if. -.has_first do.
                        chosen =. number
                    end.
                    has_first =. 1
                else.
                    has_follow =. 1
                end.
            end.
            choices =. chosen (<lhs,column)}choices
            if. 1<#numbers do.
                kind =. 'FOLLOW/FOLLOW'
                if. has_first do.
                    kind =. 'FIRST/FIRST'
                    if. has_follow do.
                        kind =. 'FIRST/FOLLOW'
                    end.
                end.
                conflicts =. conflicts,<(<lhs),(<column),(<numbers),(<kind),<chosen
            end.
        end.
    end.
    (<productions),(<predict),(<reasons),(<cells),(<choices),<conflicts
)
