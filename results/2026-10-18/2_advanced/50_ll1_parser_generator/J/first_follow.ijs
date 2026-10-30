terminal_order =: 3 : 0
    values =. /:~~.y
    result =. values-.<'$'
    if. (<'$')e.values do.
        result =. result,<'$'
    end.
    result
)
known_terminals =: 3 : 0
    result =. 0$a:
    for_alternatives. y do.
        for_rhs. >alternatives do.
            for_symbol. >rhs do.
                if. -.is_nt >symbol do.
                    result =. result,symbol
                end.
            end.
        end.
    end.
    /:~~.result
)
first_sequence =: 4 : 0
    'order nullable first' =. x
    result =. 0$a:
    for_symbol. y do.
        symbol =. >symbol
        if. -.is_nt symbol do.
            result =. ~.result,<symbol
            (<result),<0 return.
        end.
        index =. order i.<symbol
        result =. ~.result,index{::first
        if. -.index{nullable do.
            (<result),<0 return.
        end.
    end.
    (<result),<1
)
analyze_sets =: 3 : 0
    'order rules start' =. y
    nullable =. (#order)$0
    first =. (#order)$<0$a:
    follow =. (#order)$<0$a:
    passes =. 0 0 0
    changed =. 1
    while. changed do.
        changed =. 0
        passes =. (1+0{passes)0}passes
        for_lhs. i.#order do.
            if. lhs{nullable do.
                continue.
            end.
            for_box. lhs{::rules do.
                rhs =. >box
                empty =. 1
                for_symbol. rhs do.
                    if. -.is_nt >symbol do.
                        empty =. 0
                        break.
                    end.
                    if. -. (order i.symbol){nullable do.
                        empty =. 0
                        break.
                    end.
                end.
                if. empty do.
                    nullable =. 1 lhs}nullable
                    changed =. 1
                    break.
                end.
            end.
        end.
    end.
    changed =. 1
    while. changed do.
        changed =. 0
        passes =. (1+1{passes)1}passes
        for_lhs. i.#order do.
            for_rhs. lhs{::rules do.
                'values empty' =. ((<order),(<nullable),<first)first_sequence >rhs
                before =. lhs{::first
                merged =. ~.before,values
                if. (#merged)>#before do.
                    first =. (<merged)lhs}first
                    changed =. 1
                end.
            end.
        end.
    end.
    follow =. (<,<'$')(order i.<start)}follow
    changed =. 1
    while. changed do.
        changed =. 0
        passes =. (1+2{passes)2}passes
        for_lhs. i.#order do.
            for_box. lhs{::rules do.
                rhs =. >box
                for_position. i.#rhs do.
                    symbol =. position{::rhs
                    if. -.is_nt symbol do.
                        continue.
                    end.
                    index =. order i.<symbol
                    'values empty' =. ((<order),(<nullable),<first)first_sequence (position+1)}.rhs
                    if. empty do.
                        values =. ~.values,lhs{::follow
                    end.
                    before =. index{::follow
                    merged =. ~.before,values
                    if. (#merged)>#before do.
                        follow =. (<merged)index}follow
                        changed =. 1
                    end.
                end.
            end.
        end.
    end.
    (<nullable),(<first),(<follow),(<passes),<known_terminals rules
)
