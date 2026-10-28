read_instance =: 3 : 0
    rows =. <;._2 (1!:1 <y)
    'job_count MachineCount' =: num&>' 'split 0{::rows
    JobNumbers =: JobWork =: i.0
    JobOps =: 14$<i.0
    Operations =: 0 9$0
    Errors =: 0$a:
    for_number. 1+i.job_count do.
        tokens =. ' 'split number{::rows
        route =. durations =. i.0
        problem =. ''
        for_index. i.#tokens do.
            'machine duration' =. num&>':'split index{::tokens
            if. (machine<1)+.machine>MachineCount do. problem =. 'unknown machine ',":machine
            elseif. (duration<1)+.duration>99 do. problem =. 'bad duration ',":duration
            elseif. machine e.route do. problem =. 'repeated machine ',":machine end.
            if. #problem do.
                Errors =: Errors,<('job ',(":number),' operation ',(":index+1),': ',problem)
                break.
            end.
            route =. route,machine
            durations =. durations,duration
        end.
        if. #problem do. continue. end.
        work =. +/durations
        head =. 0
        identifiers =. i.0
        for_index. i.#route do.
            ident =. #Operations
            previous =. _1
            following =. _1
            if. index>0 do. previous =. ident-1 end.
            if. index< <:#route do. following =. ident+1 end.
            row =. ident,number,(index+1),(index{route),(index{durations),head,(work-(head+index{durations)),previous,following
            Operations =: Operations,row
            identifiers =. identifiers,ident
            head =. head+index{durations
        end.
        JobNumbers =: JobNumbers,number
        JobWork =: JobWork,work
        JobOps =: (<identifiers)number}JobOps
    end.
    Count =: #Operations
    Durations =: 4{"1 Operations
    MachineOps =: 0$a:
    Loads =: Heads =: Tails =: Bounds =: i.0
    for_machine. 1+i.MachineCount do.
        ids =. I.machine=3{"1 Operations
        load =. +/ids{Durations
        head =. <./5{"1 ids{Operations
        tail =. <./6{"1 ids{Operations
        MachineOps =: MachineOps,<ids
        Loads =: Loads,load
        Heads =: Heads,head
        Tails =: Tails,tail
        Bounds =: Bounds,head+load+tail
    end.
    i.0
)
operation_code =: 3 : '(''J'',(": (<y,1){Operations)),''-'',":(<y,2){Operations'
job_letter =: 3 : '(y-1){''ABCDEFGHIJKLM'''
