giffler_thompson =: 4 : 0
    rule =. x
    gene_positions =. y
    starts =. Count$0
    next_index =. ready =. 14$0
    free =. MachineCount$0
    decisions =. ties =. 0
    for_step. i.Count do.
        candidates =. earliest =. i.0
        cutoff =. chosen_machine =. 2147483647
        for_job. JobNumbers do.
            operations =. job{::JobOps
            position =. job{next_index
            if. position>:#operations do. continue. end.
            ident =. position{operations
            machine =. (<ident,3){Operations
            start =. (job{ready)>.(machine-1){free
            completion =. start+ident{Durations
            candidates =. candidates,ident
            earliest =. earliest,start
            if. (completion<cutoff)+.((completion=cutoff)*.machine<chosen_machine) do.
                cutoff =. completion
                chosen_machine =. machine
            end.
        end.
        chosen =. _1
        minimum =. 2147483647
        conflict_count =. minimum_count =. 0
        for_position. i.#candidates do.
            ident =. position{candidates
            row =. ident{Operations
            if. ((3{row)~:chosen_machine)+.(position{earliest)>:cutoff do. continue. end.
            conflict_count =. conflict_count+1
            select. rule
            case. 'SPT' do. value =. ident{Durations
            case. 'LPT' do. value =. -ident{Durations
            case. 'MWKR' do. value =. -(4{row)+6{row
            case. 'FIFO' do. value =. (1{row){ready
            case. do. value =. ident{gene_positions
            end.
            if. value<minimum do.
                minimum =. value
                chosen =. position
                minimum_count =. 1
            elseif. value=minimum do. minimum_count =. minimum_count+1 end.
        end.
        decisions =. decisions+conflict_count>1
        ties =. ties+minimum_count>1
        ident =. chosen{candidates
        start =. chosen{earliest
        job =. (<ident,1){Operations
        completion =. start+ident{Durations
        starts =. start ident}starts
        ready =. completion job}ready
        free =. completion(chosen_machine-1)}free
        next_index =. (>:(job{next_index))job}next_index
    end.
    (<starts),(<decisions),<ties
)
