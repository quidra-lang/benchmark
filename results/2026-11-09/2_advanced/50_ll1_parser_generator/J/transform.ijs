fresh_name =: 4 : 0
    name =. y
    while. 1 do.
        name =. (}:name),'''>'
        if. -. (<name)e.x do.
            name return.
        end.
    end.
)
leading_reachable =: 4 : 0
    'initial target' =. x
    'order rules start' =. y
    initial =. order i.<initial
    queue =. ,initial
    visited =. (i.#order)=initial
    cursor =. 0
    while. cursor<#queue do.
        lhs =. cursor{queue
        cursor =. cursor+1
        for_rhs. lhs{::rules do.
            rhs =. >rhs
            if. 0=#rhs do.
                continue.
            end.
            symbol =. 0{::rhs
            if. symbol-:target do.
                1 return.
            end.
            next =. order i.<symbol
            if. next<#order do.
                if. -.next{visited do.
                    visited =. 1 next}visited
                    queue =. queue,next
                end.
            end.
        end.
    end.
    0
)
eliminate_recursion =: 3 : 0
    'order rules start' =. y
    original_order =. order
    log =. 0$a:
    for_original. i.#original_order do.
        lhs_name =. original{::original_order
        for_earlier. i.original do.
            lhs =. order i.<lhs_name
            other =. earlier{::original_order
            starts =. 0
            for_rhs. lhs{::rules do.
                rhs =. >rhs
                if. #rhs do.
                    if. other-:0{::rhs do.
                        starts =. 1
                        break.
                    end.
                end.
            end.
            model =. (<order),(<rules),<start
            if. starts*.((<other),<lhs_name)leading_reachable model do.
                replaced =. 0$a:
                for_rhs. lhs{::rules do.
                    rhs =. >rhs
                    substitute =. 0
                    if. #rhs do.
                        substitute =. other-:0{::rhs
                    end.
                    if. substitute do.
                        other_index =. order i.<other
                        for_alternative. other_index{::rules do.
                            replaced =. replaced,< (>alternative),}.rhs
                        end.
                    else.
                        replaced =. replaced,<rhs
                    end.
                end.
                rules =. (<~.replaced)lhs}rules
                log =. log,<'substitute ',other,' into ',lhs_name
            end.
        end.
        lhs =. order i.<lhs_name
        retained =. 0$a:
        recursive =. 0$a:
        ordinary =. 0$a:
        for_rhs. lhs{::rules do.
            rhs =. >rhs
            cycle =. 0
            if. 1=#rhs do.
                cycle =. lhs_name-:0{::rhs
            end.
            if. cycle do.
                log =. log,<'remove cycle ',lhs_name,' -> ',lhs_name
                continue.
            end.
            retained =. retained,<rhs
            recurses =. 0
            if. #rhs do.
                recurses =. lhs_name-:0{::rhs
            end.
            if. recurses do.
                recursive =. recursive,<}.rhs
            else.
                ordinary =. ordinary,<rhs
            end.
        end.
        if. #recursive do.
            name =. order fresh_name lhs_name
            alternatives =. 0$a:
            tails =. 0$a:
            for_rhs. ordinary do.
                alternatives =. alternatives,< (>rhs),<name
            end.
            for_rhs. recursive do.
                tails =. tails,< (>rhs),<name
            end.
            tails =. tails,<0$a:
            rules =. (<alternatives)lhs}rules
            order =. ((lhs+1){.order),(<name),(lhs+1)}.order
            rules =. ((lhs+1){.rules),(<tails),(lhs+1)}.rules
            log =. log,<'eliminate left recursion in ',lhs_name,' with ',name
        else.
            rules =. (<retained)lhs}rules
        end.
    end.
    model =. (<order),(<rules),<start
    (<model),<log
)
left_factor =: 3 : 0
    'order rules start' =. y
    log =. 0$a:
    cursor =. 0
    while. cursor<#order do.
        lhs_name =. cursor{::order
        alternatives =. 0$a:
        seen =. 0$a:
        created =. 0$a:
        created_rules =. 0$a:
        original =. cursor{::rules
        for_rhs. original do.
            rhs =. >rhs
            if. 0=#rhs do.
                alternatives =. alternatives,<rhs
                continue.
            end.
            first =. 0{rhs
            if. first e.seen do.
                continue.
            end.
            seen =. seen,first
            group =. 0$a:
            for_member. original do.
                member =. >member
                if. #member do.
                    if. first-:0{member do.
                        group =. group,<member
                    end.
                end.
            end.
            if. 1=#group do.
                alternatives =. alternatives,<rhs
                continue.
            end.
            length =. #rhs
            for_member. group do.
                member =. >member
                length =. length<.#member
                matching =. 0
                while. matching<length do.
                    if. -. (matching{rhs)-:matching{member do.
                        break.
                    end.
                    matching =. matching+1
                end.
                length =. matching
            end.
            name =. (order,created)fresh_name lhs_name
            prefix =. length{.rhs
            alternatives =. alternatives,<prefix,<name
            created =. created,<name
            remainders =. 0$a:
            for_member. group do.
                remainders =. remainders,<length}.>member
            end.
            created_rules =. created_rules,<remainders
            log =. log,<'left factor ',lhs_name,' on ',(alt_text prefix),' with ',name
        end.
        rules =. (<alternatives)cursor}rules
        order =. ((cursor+1){.order),created,(cursor+1)}.order
        rules =. ((cursor+1){.rules),created_rules,(cursor+1)}.rules
        cursor =. cursor+1
    end.
    model =. (<order),(<rules),<start
    (<model),<log
)
