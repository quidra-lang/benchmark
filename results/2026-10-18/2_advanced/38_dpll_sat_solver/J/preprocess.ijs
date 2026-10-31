preprocess =: 3 : 0
    'variables original use_pure' =. y
    working =. 0$a:
    fixed =. variables$_1
    counts =. 8$0
    records =. 4$<i.0
    for_index. i.#original do.
        clause =. index{::original
        if. +./(-clause)e.clause do.
            counts =. (1+0{counts)0}counts
            records =. (<(0{::records),index+1)0}records
        else.
            reduced =. ~.clause
            counts =. ((1{counts)+(#clause)-#reduced)1}counts
            working =. working,<(<index+1),<reduced
        end.
    end.
    empty_clause =. _1
    while. 1 do.
        unit =. 0
        for_box. working do.
            'number clause' =. >box
            if. 0=#clause do.
                empty_clause =. number
                break.
            end.
        end.
        if. empty_clause>:0 do.
            break.
        end.
        for_box. working do.
            clause =. 1{::>box
            if. 1=#clause do.
                unit =. {.clause
                break.
            end.
        end.
        if. unit=0 do.
            break.
        end.
        fixed =. (unit>0)((|unit)-1)}fixed
        counts =. (1+2{counts)2}counts
        surviving =. 0$a:
        for_box. working do.
            'number clause' =. >box
            if. unit e.clause do.
                counts =. (1+3{counts)3}counts
                records =. (<(1{::records),number)1}records
            else.
                reduced =. clause#~clause~:-unit
                surviving =. surviving,<(<number),<reduced
            end.
        end.
        working =. surviving
    end.
    if. empty_clause<0 do.
        removed =. (#working)$0
        sets =. ((#working),(1+2*variables))$0
        for_index. i.#working do.
            clause =. 1{::index{::working
            row =. 1 (variables+clause)}(1+2*variables)$0
            sets =. row index}sets
        end.
        for_second. i.#working do.
            b =. 1{::second{::working
            for_first. i.#working do.
                if. first=second do.
                    continue.
                end.
                a =. 1{::first{::working
                if. ((#a)<#b)+.first<second do.
                    if. */(variables+a){second{sets do.
                        removed =. 1 second}removed
                        break.
                    end.
                end.
            end.
        end.
        surviving =. 0$a:
        for_index. i.#working do.
            entry =. index{::working
            if. index{removed do.
                counts =. (1+4{counts)4}counts
                records =. (<(2{::records),0{::entry)2}records
            else.
                surviving =. surviving,<entry
            end.
        end.
        working =. surviving
        if. use_pure do.
            while. 1 do.
                present =. (1+2*variables)$0
                for_box. working do.
                    clause =. 1{::>box
                    present =. 1 (variables+clause)}present
                end.
                pure =. (1+2*variables)$0
                pure_count =. 0
                for_variable. 1+i.variables do.
                    positive =. (variables+variable){present
                    negative =. (variables-variable){present
                    if. positive~:negative do.
                        literal =. variable
                        if. negative do.
                            literal =. -variable
                        end.
                        pure =. 1 (variables+literal)}pure
                        fixed =. (literal>0)(variable-1)}fixed
                        pure_count =. pure_count+1
                    end.
                end.
                if. pure_count=0 do.
                    break.
                end.
                counts =. ((5{counts)+pure_count)5}counts
                surviving =. 0$a:
                for_box. working do.
                    'number clause' =. >box
                    if. +./(variables+clause){pure do.
                        counts =. (1+6{counts)6}counts
                        records =. (<(3{::records),number)3}records
                    else.
                        surviving =. surviving,<(<number),<clause
                    end.
                end.
                working =. surviving
            end.
        end.
    end.
    counts =. (+/0 3 4 6{counts)7}counts
    records =. /:~&.>records
    clauses =. 1&{::&.>working
    active =. 1+I.fixed<0
    (<clauses),(<fixed),(<active),(<counts),(<records),(<empty_clause),<use_pure
)
