subtype =: 4 : 0
    current =. x
    while. #current do.
        if. current-:y do.
            1 return.
        end.
        current =. (TypeNames i.<current){::TypeParents
    end.
    0
)
classify_predicates =: 3 : 0
    FluentPredicates =: (#PredicateNames)$0
    for_schema. Schemas do.
        for_literal. 3{::>schema do.
            atom =. 1{::>literal
            index =. PredicateNames i.0{atom
            FluentPredicates =: 1 index}FluentPredicates
        end.
    end.
)
substitute =: 4 : 0
    'names arguments' =. x
    'predicate terms' =. y
    mapped =. (names i.terms){arguments
    (<predicate),<mapped
)
objects_of_type =: 4 : 0
    'objects types' =. x
    selected =. 0$a:
    for_i. i.#objects do.
        if. (i{::types)subtype y do.
            selected =. selected,i{objects
        end.
    end.
    selected
)
parameter_combinations =: 3 : 0
    combinations =. ,<0$a:
    for_choice. y do.
        next =. 0$a:
        for_prefix. combinations do.
            for_object. >choice do.
                next =. next,< (>prefix),object
            end.
        end.
        combinations =. next
    end.
    combinations
)
fluent_atoms =: 3 : 0
    selected =. 0$a:
    for_atom. y do.
        atom =. >atom
        if. (PredicateNames i.0{atom){FluentPredicates do.
            selected =. selected,<atom
        end.
    end.
    selected
)
fact_set =: 4 : 0
    numbers =. x i.y
    numbers =. numbers#~numbers<#x
    bits =. (#x)$0
    1 numbers}bits
)
ground_problem =: 3 : 0
    source =. y
    'name objects types initial_atoms goal_atoms diagnostics' =. source
    object_table =. (<objects),<types
    by_type =. 0$a:
    for_type. TypeNames do.
        by_type =. by_type,<object_table objects_of_type >type
    end.
    statistics =. ((#Schemas),3)$0
    candidates =. 0$a:
    for_si. i.#Schemas do.
        schema =. si{::Schemas
        'schema_name parameters condition effects cost' =. schema
        'parameter_names parameter_types' =. parameters
        choices =. 0$a:
        for_type. parameter_types do.
            choices =. choices,(TypeNames i.type){by_type
        end.
        assignments =. */#&>choices
        statistics =. assignments(<si,0)}statistics
        for_arguments. parameter_combinations choices do.
            arguments =. >arguments
            binding =. (<parameter_names),<arguments
            positive =. 0$a:
            negative =. 0$a:
            accepted =. 1
            for_literal. condition do.
                'sign atom' =. >literal
                bound =. binding substitute atom
                predicate =. 0{::bound
                if. predicate-:,'=' do.
                    terms =. 1{::bound
                    truth =. (0{::terms)-:1{::terms
                elseif. -. (PredicateNames i.<predicate){FluentPredicates do.
                    truth =. (<bound)e.initial_atoms
                else.
                    if. sign do.
                        positive =. positive,<bound
                    else.
                        negative =. negative,<bound
                    end.
                    continue.
                end.
                if. truth~:sign do.
                    accepted =. 0
                    break.
                end.
            end.
            if. -.accepted do.
                continue.
            end.
            adds =. 0$a:
            deletes =. 0$a:
            for_literal. effects do.
                'sign atom' =. >literal
                bound =. binding substitute atom
                if. sign do.
                    adds =. adds,<bound
                else.
                    deletes =. deletes,<bound
                end.
            end.
            adds =. ~.adds
            deletes =. (~.deletes)-.adds
            candidate =. (<si),(<arguments),(<cost),(<~.positive),(<~.negative),(<adds),<deletes
            candidates =. candidates,<candidate
            statistics =. (1+(<si,1){statistics)(<si,1)}statistics
        end.
    end.
    reachable =. fluent_atoms initial_atoms
    accepted =. (#candidates)$0
    changed =. 1
    while. changed do.
        changed =. 0
        for_index. I.-.accepted do.
            candidate =. index{::candidates
            if. */(3{::candidate)e.reachable do.
                accepted =. 1 index}accepted
                reachable =. ~.reachable,5{::candidate
                si =. 0{::candidate
                statistics =. (1+(<si,2){statistics)(<si,2)}statistics
                changed =. 1
            end.
        end.
    end.
    keys =. 0$a:
    for_atom. reachable do.
        'predicate terms' =. >atom
        key =. (PredicateNames i.<predicate),objects i.terms
        keys =. keys,<key
    end.
    facts =. (/:keys){reachable
    actions =. 0$a:
    for_index. I.accepted do.
        candidate =. index{::candidates
        action =. 3{.candidate
        for_field. 3 4 5 6 do.
            action =. action,<facts fact_set field{::candidate
        end.
        actions =. actions,<action
    end.
    initial =. facts fact_set fluent_atoms initial_atoms
    goal =. (#facts)$0
    unreachable =. 0$a:
    for_atom. goal_atoms do.
        index =. facts i.atom
        if. index<#facts do.
            goal =. 1 index}goal
        else.
            bound =. >atom
            predicate =. PredicateNames i.0{bound
            if. (predicate{FluentPredicates)+.-.atom e.initial_atoms do.
                unreachable =. unreachable,atom
            end.
        end.
    end.
    static_count =. (#initial_atoms)-#fluent_atoms initial_atoms
    result =. (<source),(<by_type),(<statistics),(<#candidates),(<facts),(<actions)
    result,(<initial),(<goal),(<unreachable),<static_count
)
