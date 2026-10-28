gene_operations =: 3 : 0
    counts =. 14$0
    result =. i.0
    for_gene. y do.
        result =. result,(gene{counts){gene{::JobOps
        counts =. (>:(gene{counts))gene}counts
    end.
    result
)
decode =: 3 : 0
    starts =. Count$0
    ready =. 14$0
    free =. MachineCount$0
    for_ident. gene_operations y do.
        job =. (<ident,1){Operations
        machine =. _1+(<ident,3){Operations
        start =. (job{ready)>.machine{free
        completion =. start+ident{Durations
        starts =. start ident}starts
        ready =. completion job}ready
        free =. completion machine}free
    end.
    starts
)
tournament =: 4 : 0
    best =. _1
    for_i. i.y do.
        index =. below #x
        if. best<0 do. best =. index
        elseif. ((index{x)<best{x)+.(((index{x)=best{x)*.index<best) do. best =. index end.
    end.
    best
)
preserve_order =: 3 : 0
    'keeper donor kept' =. y
    fillers =. donor#~-.donor e.kept
    result =. keeper
    result =. fillers(I.-.keeper e.kept)}result
    result
)
crossover =: 4 : 0
    kept =. i.0
    for_job. JobNumbers do. if. 0=below 2 do. kept =. kept,job end. end.
    first =. preserve_order (<x),(<y),<kept
    second =. preserve_order (<y),(<x),<kept
    (<first),<second
)
swap_mutation =: 3 : 0
    first =. below #y
    second =. below #y
    held =. first{y
    result =. (second{y)first}y
    held second}result
)
insert_mutation =: 3 : 0
    source =. below #y
    target =. below #y
    held =. source{y
    remaining =. (source{.y),(source+1)}.y
    (target{.remaining),held,target}.remaining
)
