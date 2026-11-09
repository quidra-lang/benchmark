literal_value =: 3 : 0
    truth =. ((|y)-1){RoundAssignment
    if. truth<0 do.
        _1
    elseif. y>0 do.
        truth
    else.
        1-truth
    end.
)
assign_literal =: 3 : 0
    'literal kind' =. y
    RoundAssignment =: (literal>0)((|literal)-1)}RoundAssignment
    RoundTrail =: RoundTrail,literal,kind
    RoundTrace =: RoundTrace,<((kind{'DFP'),text literal)
    0
)
record_conflict =: 3 : 0
    RoundConflicts =: RoundConflicts+1
    RoundTrace =: RoundTrace,<'C'
    0
)
run_round =: 3 : 0
    'variables clauses' =. y
    RoundAssignment =: variables$_1
    RoundTrail =: 0 2$0
    RoundTrace =: 0$a:
    RoundDecisions =: 0
    RoundPropagations =: 0
    RoundConflicts =: 0
    RoundMaxDepth =: 0
    watches =. (1+2*variables)$<i.0
    queue_head =. 0
    for_index. i.#clauses do.
        clause =. index{::clauses
        if. 2<:#clause do.
            for_literal. 2{.clause do.
                watched =. variables+literal
                watches =. (<(watched{::watches),index)watched}watches
            end.
        end.
    end.
    for_box. clauses do.
        clause =. >box
        if. 0=#clause do.
            record_conflict 0
            (<0),(<i.0),(<RoundTrace),<RoundDecisions,RoundPropagations,RoundConflicts,RoundMaxDepth return.
        end.
        if. 1=#clause do.
            truth =. literal_value {.clause
            if. truth=0 do.
                record_conflict 0
                (<0),(<i.0),(<RoundTrace),<RoundDecisions,RoundPropagations,RoundConflicts,RoundMaxDepth return.
            elseif. truth<0 do.
                assign_literal ({.clause),2
                RoundPropagations =: RoundPropagations+1
            end.
        end.
    end.
    finished =. 0
    satisfiable =. 0
    while. -.finished do.
        found_conflict =. 0
        while. queue_head<#RoundTrail do.
            false_literal =. -(<queue_head,0){RoundTrail
            queue_head =. queue_head+1
            watched =. variables+false_literal
            watch_list =. watched{::watches
            index =. 0
            while. index<#watch_list do.
                clause_id =. index{watch_list
                clause =. clause_id{::clauses
                if. false_literal=0{clause do.
                    clause =. (1 0{clause)0 1}clause
                    clauses =. (<clause)clause_id}clauses
                end.
                other =. 0{clause
                if. 1=literal_value other do.
                    index =. index+1
                    continue.
                end.
                substitute =. _1
                for_position. 2+i.(#clause)-2 do.
                    if. 0~:literal_value position{clause do.
                        substitute =. position
                        break.
                    end.
                end.
                if. substitute>:0 do.
                    saved =. 1{clause
                    clause =. (substitute{clause)1}clause
                    clause =. saved substitute}clause
                    clauses =. (<clause)clause_id}clauses
                    watch_list =. (index{.watch_list),(index+1)}.watch_list
                    new_watch =. variables+1{clause
                    watches =. (<(new_watch{::watches),clause_id)new_watch}watches
                    continue.
                end.
                truth =. literal_value other
                if. truth=0 do.
                    record_conflict 0
                    found_conflict =. 1
                    break.
                elseif. truth<0 do.
                    assign_literal other,2
                    RoundPropagations =: RoundPropagations+1
                end.
                index =. index+1
            end.
            watches =. (<watch_list)watched}watches
            if. found_conflict do.
                break.
            end.
        end.
        if. found_conflict do.
            while. #RoundTrail do.
                'literal kind' =. {:RoundTrail
                if. kind=0 do.
                    break.
                end.
                RoundAssignment =: _1 ((|literal)-1)}RoundAssignment
                RoundTrail =: }:RoundTrail
            end.
            if. 0=#RoundTrail do.
                finished =. 1
            else.
                decision =. (<((#RoundTrail)-1),0){RoundTrail
                RoundAssignment =: _1 ((|decision)-1)}RoundAssignment
                RoundTrail =: }:RoundTrail
                assign_literal (-decision),1
                queue_head =. (#RoundTrail)-1
            end.
        else.
            counts =. (1+2*variables)$0
            for_box. clauses do.
                clause =. >box
                values =. literal_value"0 clause
                if. 1 e.values do.
                    continue.
                end.
                for_literal. (values<0)#clause do.
                    location =. variables+literal
                    counts =. (1+location{counts)location}counts
                end.
            end.
            best =. 0
            maximum =. 0
            for_variable. 1+i.variables do.
                for_literal. variable,-variable do.
                    count =. (variables+literal){counts
                    if. count>maximum do.
                        maximum =. count
                        best =. literal
                    end.
                end.
            end.
            if. best=0 do.
                satisfiable =. 1
                finished =. 1
            else.
                assign_literal best,0
                RoundDecisions =: RoundDecisions+1
                depth =. +/(1{"1 RoundTrail)e.0 1
                RoundMaxDepth =: RoundMaxDepth>.depth
            end.
        end.
    end.
    (<satisfiable),(<RoundAssignment=1),(<RoundTrace),<RoundDecisions,RoundPropagations,RoundConflicts,RoundMaxDepth
)
