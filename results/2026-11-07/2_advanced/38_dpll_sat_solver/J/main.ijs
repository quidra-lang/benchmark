load 'cnf_io.ijs'
load 'encoders.ijs'
load 'preprocess.ijs'
load 'dpll.ijs'
load 'report.ijs'
Commands =: ;:'SOLVE ENUM CORE QUEENS PIGEON COLOR CHROMATIC'
ArgumentTypes =: (<;:'file'),(<;:'file limit'),(<;:'file'),(<;:'small limit'),(<;:'small small limit'),(<;:'graph color limit'),<;:'graph color'
graph_name =: 0&{::
graph_vertices =: 1&{::
graph_edges =: 2&{::
graph_error =: 3&{::
graph_colors =: 4&{::
graph_used =: 5&{::
graph_degree =: 6&{::
job_number =: 0&{::
job_text =: 1&{::
job_command =: 2&{::
job_args =: 3&{::
job_error =: 4&{::
job_graph =: 5&{::
job_colors =: 6&{::
job_solution =: 7&{::
job_attempts =: 8&{::
job_stats =: 9&{::
job_rounds =: 10&{::
job_removed =: 11&{::
job_core =: 12&{::
job_analysis =: 13&{::
sol_variables =: 0&{::
sol_clauses =: 1&{::
sol_models =: 2&{::
sol_status =: 3&{::
sol_rounds =: 4&{::
sol_stop =: 5&{::
sol_trace =: 6&{::
sol_stats =: 7&{::
sol_preparation =: 8&{::
sol_removed =: 9&{::
sol_colors =: 10&{::
add_stats =: 4 : '(3{.x+y),(3{x)>.3{y'
finish_graph =: 3 : 0
    'name vertices edges reason' =. y
    edges =. /:~edges
    neighbors =. (vertices,vertices)$0
    degree =. vertices$0
    for_edge. edges do.
        'first second' =. edge-1
        neighbors =. 1 (<first,second)}neighbors
        neighbors =. 1 (<second,first)}neighbors
        degree =. (1+first{degree)first}degree
        degree =. (1+second{degree)second}degree
    end.
    order =. /:(-degree),.i.vertices
    colors =. vertices$0
    for_vertex. order do.
        present =. (vertex{neighbors)#colors
        candidate =. 1
        while. candidate e.present do.
            candidate =. candidate+1
        end.
        colors =. candidate vertex}colors
    end.
    (<name),(<vertices),(<edges),(<reason),(<colors),(< >./colors),< >./degree
)
load_graphs =: 3 : 0
    graphs =. 0$a:
    current =. 0
    lines =. read_lines 'input/graphs.txt'
    for_index. i.#lines do.
        line =. index{::lines
        if. -.current do.
            if. 0=#line do.
                continue.
            end.
            if. '#'={.line do.
                continue.
            end.
            header =. words line
            name =. 1{::header
            vertices =. num 2{::header
            edges =. 0 2$0
            reason =. ''
            current =. 1
        elseif. line-:'END' do.
            graphs =. graphs,<finish_graph (<name),(<vertices),(<edges),<reason
            current =. 0
        elseif. 0=#reason do.
            tokens =. words line
            issue =. ''
            valid =. 2=#tokens
            if. valid do.
                valid =. *./valid_number&>tokens
            end.
            if. -.valid do.
                issue =. 'bad edge line'
            else.
                pair =. num&>tokens
                if. +./(pair<1)+.pair>vertices do.
                    issue =. 'vertex out of range'
                elseif. =/pair do.
                    issue =. 'self loop'
                else.
                    pair =. /:~pair
                    if. (<pair)e.<"1 edges do.
                        issue =. 'duplicate edge'
                    else.
                        edges =. edges,pair
                    end.
                end.
            end.
            if. #issue do.
                reason =. issue,' at line ',text index+1
            end.
        end.
    end.
    graphs
)
load_jobs =: 3 : 0
    jobs =. 0$a:
    for_box. read_lines 'input/jobs.txt' do.
        line =. >box
        if. 0=#line do.
            continue.
        end.
        if. '#'={.line do.
            continue.
        end.
        tokens =. words line
        record =. (<1+#jobs),(<line),(<0{::tokens),(<}.tokens),(<''),(<_1),(<0),(<0$a:),(<0$a:),(<4$0),(<0),(<0),(<0$a:),<0$a:
        jobs =. jobs,<record
    end.
    jobs
)
validate =: 3 : 0
    command =. job_command y
    args =. job_args y
    command_index =. Commands i.<command
    if. command_index=#Commands do.
        'unknown command ',command return.
    end.
    kinds =. command_index{::ArgumentTypes
    if. (#kinds)~:#args do.
        'wrong argument count' return.
    end.
    for_index. i.#args do.
        token =. index{::args
        kind =. index{::kinds
        if. kind-:'file' do.
            valid =. (5<:#token)*.(#token)<:24
            if. valid do.
                stem =. _4}.token
                valid =. ('.cnf'-:_4{.token)*.*./stem e.'abcdefghijklmnopqrstuvwxyz0123456789_'
            end.
            if. -.valid do.
                'bad file name ',token return.
            end.
        elseif. kind-:'graph' do.
            location =. (graph_name&.>Graphs)i.<token
            if. location=#Graphs do.
                'unknown graph ',token return.
            end.
            reason =. graph_error location{::Graphs
            if. #reason do.
                'invalid graph ',token,': ',reason return.
            end.
        else.
            if. -.valid_number token do.
                'bad number ',token return.
            end.
            maximum =. 200
            if. kind-:'small' do.
                maximum =. 8
            elseif. kind-:'color' do.
                maximum =. 6
            end.
            value =. num token
            if. (value<1)+.value>maximum do.
                'out of range ',token return.
            end.
        end.
    end.
    ''
)
solve_formula =: 3 : 0
    'variables clauses limit' =. y
    preparation =. preprocess (<variables),(<clauses),<limit=1
    'simplified fixed active counts records empty pure' =. preparation
    models =. 0$a:
    blocking =. 0$a:
    counters =. 4$0
    events =. 0$a:
    rounds =. 0
    stop =. 'limit'
    if. empty>:0 do.
        stop =. 'preprocess'
    else.
        while. (#models)<limit do.
            rounds =. rounds+1
            'satisfiable model trace stats' =. run_round (<variables),<simplified,blocking
            if. rounds=1 do.
                events =. trace
            end.
            counters =. counters add_stats stats
            if. -.satisfiable do.
                stop =. 'all'
                break.
            end.
            fixed_indices =. I.fixed>:0
            model =. (fixed_indices{fixed)fixed_indices}model
            models =. models,<model
            block =. active*(1-2*(active-1){model)
            blocking =. blocking,<block
        end.
    end.
    status =. 'UNSAT'
    if. #models do.
        status =. 'SAT'
    end.
    (<variables),(<clauses),(<models),(<status),(<rounds),(<stop),(<events),(<counters),(<preparation),(<7{counts),<0
)
true_count =: 4 : '+/(((|y)-1){x)=y>0'
satisfies =: 4 : 0
    for_box. y do.
        if. 0=x true_count >box do.
            0 return.
        end.
    end.
    1
)
analyze =: 3 : 0
    variables =. sol_variables y
    clauses =. sol_clauses y
    models =. sol_models y
    if. 0=#models do.
        0$a: return.
    end.
    failure =. i.0
    distribution =. i.0
    for_index. i.#models do.
        model =. index{::models
        for_clause_index. i.#clauses do.
            count =. model true_count clause_index{::clauses
            if. index=0 do.
                distribution =. distribution,count
            end.
            if. (count=0)*.0=#failure do.
                failure =. (index+1),clause_index+1
            end.
        end.
    end.
    first =. 0{::models
    safe =. i.0
    backbone =. i.0
    for_variable. i.variables do.
        flipped =. (1-variable{first)variable}first
        if. flipped satisfies clauses do.
            safe =. safe,variable+1
        end.
        if. *./(variable{first)=variable{&>models do.
            backbone =. backbone,(variable+1)*((2*variable{first)-1)
        end.
    end.
    diversity =. i.0
    for_first_index. i.#models do.
        for_second_index. (first_index+1)+i.(#models)-(first_index+1) do.
            diversity =. diversity,+/(first_index{::models)~:second_index{::models
        end.
    end.
    (<failure),(<distribution),(<safe),(<diversity),<backbone
)
unsat_core =: 3 : 0
    'variables clauses' =. y
    remaining =. (#clauses)$1
    decisions =. 0
    conflicts =. 0
    for_remove. i.#clauses do.
        selected =. 0 remove}remaining
        solution =. solve_formula (<variables),(<selected#clauses),<1
        stats =. sol_stats solution
        decisions =. decisions+0{stats
        conflicts =. conflicts+2{stats
        if. 'UNSAT'-:sol_status solution do.
            remaining =. selected
        end.
    end.
    (<1+I.remaining),(<decisions),<conflicts
)
execute_job =: 3 : 0
    job =. y
    reason =. validate job
    if. #reason do.
        (<reason)4}job return.
    end.
    args =. job_args job
    command =. job_command job
    if. command-:'CHROMATIC' do.
        graph_index =. (graph_name&.>Graphs)i.0{args
        graph =. graph_index{::Graphs
        attempts =. 0$a:
        counters =. 4$0
        rounds =. 0
        removed =. 0
        for_colors. 1+i.num 1{::args do.
            'variables clauses reason' =. coloring (<graph_vertices graph),(<graph_edges graph),<colors
            solution =. solve_formula (<variables),(<clauses),<1
            solution =. (<colors)10}solution
            attempts =. attempts,<solution
            counters =. counters add_stats sol_stats solution
            rounds =. rounds+sol_rounds solution
            removed =. removed+sol_removed solution
            if. 'SAT'-:sol_status solution do.
                break.
            end.
        end.
        job =. (<graph_index)5}job
        job =. (<colors)6}job
        job =. (<attempts)8}job
    else.
        if. (<command)e.;:'SOLVE ENUM CORE' do.
            'variables clauses reason' =. read_dimacs 0{::args
            if. #reason do.
                (<reason)4}job return.
            end.
            limit =. 1
            if. command-:'ENUM' do.
                limit =. num 1{::args
            end.
        elseif. command-:'QUEENS' do.
            'variables clauses reason' =. queens num 0{::args
            limit =. num 1{::args
        elseif. command-:'PIGEON' do.
            'variables clauses reason' =. pigeon num&>2{.args
            limit =. num 2{::args
        else.
            graph_index =. (graph_name&.>Graphs)i.0{args
            graph =. graph_index{::Graphs
            colors =. num 1{::args
            'variables clauses reason' =. coloring (<graph_vertices graph),(<graph_edges graph),<colors
            limit =. num 2{::args
            job =. (<graph_index)5}job
            job =. (<colors)6}job
        end.
        solution =. solve_formula (<variables),(<clauses),<limit
        counters =. sol_stats solution
        rounds =. sol_rounds solution
        removed =. sol_removed solution
        if. (command-:'CORE')*.'UNSAT'-:sol_status solution do.
            core =. unsat_core (<variables),<clauses
            job =. (<core)12}job
        end.
    end.
    job =. (<solution)7}job
    job =. (<counters)9}job
    job =. (<rounds)10}job
    job =. (<removed)11}job
    job =. (<analyze solution)13}job
    job
)
heading =: 3 : '''JOB '',(text job_number y),'' '',job_text y'
formula_summary =: 3 : 0
    'variables clauses' =. y
    lengths =. #&>clauses
    'variables=',(text variables),' clauses=',(text #clauses),' literals=',(text +/lengths),' lengths=',frequency lengths
)
graph_summary =: 3 : 0
    'graph vertices=',(text graph_vertices y),' edges=',(text #graph_edges y),' max_degree=',(text graph_degree y),' greedy=',text graph_used y
)
preprocessing_report =: 3 : 0
    'clauses fixed active counts records empty pure' =. y
    values =. (<pure{::'off';'on'),text&.>counts
    lines =. <'preprocess ',(;:'pure tautologies duplicate_literals unit_fixed unit_removed subsumed pure_fixed pure_removed removed')named values
    lines =. lines,<'removed_clauses ',(;:'tautology unit subsumed pure')named number_list&.>records
    if. empty>:0 do.
        lines =. lines,<'simplified empty_clause=',text empty
    else.
        lengths =. #&>clauses
        indices =. I.fixed>:0
        literals =. (indices+1)*((2*indices{fixed)-1)
        lines =. lines,<'simplified clauses=',(text #clauses),' literals=',(text +/lengths),' lengths=',(frequency lengths),' fixed=',(text #indices),' active=',text #active
        lines =. lines,<'fixed literals=',number_list literals
    end.
    lines
)
search_report =: 3 : '''search '',(;:''decisions propagations conflicts max_depth'')named text&.>y'
verification_report =: 3 : 0
    'solution analysis' =. y
    failure =. 0{::analysis
    if. #failure do.
        'verify failed model=',(text 0{failure),' clause=',text 1{failure
    else.
        'verify ok models=',(text #sol_models solution),' clauses=',(text #sol_clauses solution),' true_literals=',frequency 1{::analysis
    end.
)
analysis_report =: 3 : 0
    'solution analysis' =. y
    if. 0=#analysis do.
        0$a: return.
    end.
    'failure distribution safe diversity backbone' =. analysis
    lines =. (<verification_report y),<'flips safe=',(text #safe),' variables=',number_list safe
    if. #diversity do.
        lines =. lines,<'diversity pairs=',(text #diversity),' min_distance=',(text <./diversity),' max_distance=',text >./diversity
    end.
    if. 'all'-:sol_stop solution do.
        lines =. lines,<'backbone size=',(text #backbone),' literals=',number_list backbone
    end.
    lines
)
result_paragraph =: 3 : 0
    job =. y
    lines =. <heading job
    if. #job_error job do.
        lines,<'error ',job_error job return.
    end.
    solution =. job_solution job
    if. 'CHROMATIC'-:job_command job do.
        lines =. lines,<graph_summary (job_graph job){::Graphs
        for_box. job_attempts job do.
            attempt =. >box
            values =. (<text sol_colors attempt),(<text #sol_clauses attempt),(<text sol_removed attempt),(<sol_status attempt),(<sol_stop attempt),text&.>sol_stats attempt
            lines =. lines,<'attempt ',(;:'k clauses removed result stop decisions propagations conflicts max_depth')named values
        end.
        chromatic =. '-'
        if. 'SAT'-:sol_status solution do.
            chromatic =. text job_colors job
        end.
        lines =. lines,<'result ',(sol_status solution),' chromatic=',chromatic,' attempts=',text #job_attempts job
        lines =. lines,<search_report job_stats job
        analysis =. job_analysis job
        if. #analysis do.
            lines =. lines,<verification_report (<solution),<analysis
            safe =. 2{::analysis
            lines =. lines,<'flips safe=',(text #safe),' variables=',number_list safe
        end.
    else.
        if. 'COLOR'-:job_command job do.
            lines =. lines,<graph_summary (job_graph job){::Graphs
        end.
        lines =. lines,<'formula ',formula_summary (<sol_variables solution),<sol_clauses solution
        lines =. lines,preprocessing_report sol_preparation solution
        lines =. lines,<'result ',(sol_status solution),' models=',(text #sol_models solution),' rounds=',(text sol_rounds solution),' stop=',sol_stop solution
        lines =. lines,<search_report sol_stats solution
        if. sol_rounds solution do.
            events =. sol_trace solution
            prefix =. ((12<.#events){.events)
            shown =. '-'
            if. #prefix do.
                shown =. ' 'join prefix
            end.
            if. 12<#events do.
                shown =. shown,' +',text (#events)-12
            end.
            lines =. lines,<'trace ',shown
        end.
        lines =. lines,analysis_report (<solution),<job_analysis job
        core =. job_core job
        if. #core do.
            'clauses decisions conflicts' =. core
            lines =. lines,<'core size=',(text #clauses),' decisions=',(text decisions),' conflicts=',(text conflicts),' clauses=',number_list clauses
        end.
    end.
    lines
)
canonical_queens =: 3 : 0
    n =. #y
    variants =. (0,n)$0
    for_transform. i.8 do.
        current =. n$0
        for_row. 1+i.n do.
            column =. (row-1){y
            select. transform
            case. 0 do.
                r =. row
                c =. column
            case. 1 do.
                r =. column
                c =. (n+1)-row
            case. 2 do.
                r =. (n+1)-row
                c =. (n+1)-column
            case. 3 do.
                r =. (n+1)-column
                c =. row
            case. 4 do.
                r =. row
                c =. (n+1)-column
            case. 5 do.
                r =. (n+1)-row
                c =. column
            case. 6 do.
                r =. column
                c =. row
            case. 7 do.
                r =. (n+1)-column
                c =. (n+1)-row
            end.
            current =. c (r-1)}current
        end.
        variants =. variants,current
    end.
    distinct =. ~.variants
    (<{./:~variants),<#distinct
)
canonical_colors =: 3 : 0
    distinct =. ~.y
    canonical =. 1+distinct i.y
    (<canonical),<#distinct
)
boards =: 3 : 0
    job =. y
    command =. job_command job
    args =. job_args job
    solution =. job_solution job
    models =. sol_models solution
    stop =. sol_stop solution
    if. 'PIGEON'-:command do.
        'pigeons holes' =. num&>2{.args
        lines =. <'PIGEON job=',(text job_number job),' pigeons=',(text pigeons),' holes=',text holes
        for_index. i.#models do.
            places =. (index{::models)positions pigeons,holes
            empty =. (1+i.holes)-.places
            lines =. lines,<'assignment ',(text index+1),' holes=',(number_list places),' empty=',number_list empty
        end.
        expected =. 0
        if. pigeons<:holes do.
            expected =. */holes-i.pigeons
        end.
        lines =. lines,<'summary assignments=',(text #models),' stop=',stop,' expected=',text expected
        lines return.
    end.
    is_queens =. 'QUEENS'-:command
    if. is_queens do.
        rows =. num 0{::args
        width =. rows
        lines =. <'QUEENS job=',(text job_number job),' n=',text rows
    else.
        graph =. (job_graph job){::Graphs
        rows =. graph_vertices graph
        width =. job_colors job
        lines =. <command,' job=',(text job_number job),' graph=',(graph_name graph),' vertices=',(text rows),' edges=',(text #graph_edges graph),' colors=',text width
        lines =. lines,<'greedy used=',(text graph_used graph),' colors=',number_list graph_colors graph
    end.
    keys =. 0$a:
    groups =. 0$a:
    for_index. i.#models do.
        places =. (index{::models)positions rows,width
        if. is_queens do.
            'canonical orbit' =. canonical_queens places
        else.
            'canonical orbit' =. canonical_colors places
        end.
        group_index =. keys i.<canonical
        first =. group_index=#keys
        if. first do.
            keys =. keys,<canonical
            group =. (<canonical),(<orbit),(<index+1),<0
            groups =. groups,<group
        end.
        group =. group_index{::groups
        group =. (<1+3{::group)3}group
        groups =. (<group)group_index}groups
        if. is_queens do.
            lines =. lines,<'solution ',(text index+1),' columns=',(number_list places),' class=',text group_index+1
            if. first do.
                lines =. lines,queens_board places
            end.
        else.
            sizes =. +/places=/1+i.width
            lines =. lines,<'coloring ',(text index+1),' colors=',(number_list places),' used=',(text orbit),' sizes=',(number_list sizes),' class=',text group_index+1
        end.
    end.
    for_index. i.#groups do.
        'canonical orbit first found' =. index{::groups
        line =. 'class ',text index+1
        if. is_queens do.
            line =. line,' orbit=',text orbit
        end.
        lines =. lines,<line,' found=',(text found),' first=',(text first),' canonical=',number_list canonical
    end.
    label =. 'colorings'
    if. is_queens do.
        label =. 'solutions'
    end.
    lines,<'summary ',label,'=',(text #models),' stop=',stop,' classes=',text #groups
)
summary =: 4 : 0
    jobs =. x
    valid =. y
    sat =. +/('SAT'&-:)&>sol_status&.>job_solution&.>valid
    totals =. 6$0
    for_box. valid do.
        job =. >box
        stats =. job_stats job
        totals =. totals+(#sol_models job_solution job),(job_rounds job),(3{.stats),job_removed job
    end.
    lines =. <'SUMMARY jobs=',(text #jobs),' sat=',(text sat),' unsat=',(text (#valid)-sat),' error=',text (#jobs)-#valid
    lines =. lines,<'totals ',(;:'models rounds decisions propagations conflicts removed_clauses')named text&.>totals
    for_command_box. Commands do.
        command =. >command_box
        count =. 0
        yes =. 0
        counters =. 3$0
        for_box. valid do.
            job =. >box
            if. command-:job_command job do.
                count =. count+1
                yes =. yes+'SAT'-:sol_status job_solution job
                counters =. counters+3{.job_stats job
            end.
        end.
        if. count do.
            values =. text&.>count,yes,(count-yes),counters
            lines =. lines,<'command ',command,' ',(;:'jobs sat unsat decisions propagations conflicts')named values
        end.
    end.
    if. #valid do.
        labels =. ;:'hardest deepest busiest'
        fields =. ;:'conflicts max_depth propagations'
        for_index. i.3 do.
            location =. index{2 3 1
            values =. location{&>job_stats&.>valid
            best =. (values i.>./values){::valid
            lines =. lines,<(index{::labels),' job=',(text job_number best),' ',(index{::fields),'=',text >./values
        end.
    end.
    lines
)
run =: 3 : 0
    Graphs =: load_graphs 0
    jobs =. load_jobs 0
    valid =. 0$a:
    results =. 0$a:
    model_output =. 0$a:
    board_output =. 0$a:
    csv =. <'job,command,status,variables,clauses,removed_clauses,decisions,propagations,conflicts,max_depth,models,rounds'
    for_box. jobs do.
        job =. execute_job >box
        results =. results,<result_paragraph job
        if. 0=#job_error job do.
            valid =. valid,<job
            solution =. job_solution job
            models =. sol_models solution
            if. #models do.
                lines =. <heading job
                for_index. i.#models do.
                    lines =. lines,<'model ',text index+1
                    lines =. lines,model_lines index{::models
                end.
                model_output =. model_output,<lines
            end.
            if. (<job_command job)e.;:'QUEENS PIGEON COLOR CHROMATIC' do.
                board_output =. board_output,<boards job
            end.
            values =. (<text job_number job),(<job_command job),(<sol_status solution),(<text sol_variables solution),(<text #sol_clauses solution),(<text job_removed job),(text&.>job_stats job),(<text #models),<text job_rounds job
            csv =. csv,<','join values
        end.
    end.
    results =. results,<jobs summary valid
    try.
        1!:5 <'output'
    catch.
    end.
    'results.txt'save_paragraphs results
    'models.txt'save_paragraphs model_output
    'boards.txt'save_paragraphs board_output
    'stats.csv'save_lines csv
    0
)
run 0
