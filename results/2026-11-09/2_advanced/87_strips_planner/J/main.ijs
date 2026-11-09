load 'pddl_parser.ijs'
load 'grounding.ijs'
load 'heuristics.ijs'
load 'search.ijs'
load 'graphplan.ijs'

intdiv =: 4 : '<.(x:x)%x:y'
integer =: 3 : 0
    text =. ,":y
    '-'(I.text='_')}text
)
parse_integer =: 3 : '".y'
join =: 4 : 0
    text =. ''
    for_i. i.#y do.
        if. i do.
            text =. text,x
        end.
        text =. text,i{::y
    end.
    text
)
split_words =: 3 : '<;._1 '' '',y'
read_lines =: 3 : 0
    selected =. 0$a:
    for_line. <;._2 (1!:1 <'input/',y) do.
        line =. >line
        if. 0=#line do.
            continue.
        end.
        if. '#'~:{.line do.
            selected =. selected,<line
        end.
    end.
    selected
)
notation =: 3 : 0
    'name arguments' =. y
    '(' ,(' 'join (<name),arguments),')'
)
number_list =: 3 : 0
    numbers =. I.y
    if. #numbers do.
        ','join integer&.>numbers
    else.
        ,'-'
    end.
)
headed =: 4 : 0
    if. #y do.
        x,' ',' 'join y
    else.
        x,' -'
    end.
)
value_text =: 3 : 0
    if. y=_1 do. 'inf' else. integer y end.
)
heuristic_text =: 3 : 0
    items =. 0$a:
    for_i. i.#HeuristicNames do.
        items =. items,<(i{::HeuristicNames),'=',value_text i{y
    end.
    ' 'join items
)
read_settings =: 3 : 0
    RunPairs =: 0$a:
    for_line. read_lines 'params.txt' do.
        fields =. split_words >line
        select. 0{::fields
        case. 'budget' do. Budget =: parse_integer 1{::fields
        case. 'weight' do. Weight =: parse_integer 1{::fields
        case. 'graphplan' do. LevelLimit =: parse_integer 1{::fields
        case. 'run' do. RunPairs =: RunPairs,<}.fields
        case. 'repair' do. RepairPair =: }.fields
        end.
    end.
    Tags =: 0$a:
    for_pair. RunPairs do.
        Tags =: Tags,<' 'join >pair
    end.
    Tags =: Tags,<'graphplan'
)
read_candidates =: 3 : 0
    Candidates =: 0$a:
    for_line. read_lines 'candidates.txt' do.
        line =. >line
        if. 'plan '-:5{.line do.
            fields =. split_words line
            problem =. 1{::fields
            label =. 2{::fields
            steps =. 0$a:
        elseif. line-:'end' do.
            candidate =. (<1+#Candidates),(<problem),(<label),<steps
            Candidates =: Candidates,<candidate
        else.
            fields =. split_words }:}.line
            steps =. steps,<expression_atom fields
        end.
    end.
)
argument_error =: 3 : 0
    'arguments expected names types noun' =. y
    if. (#arguments)~:#expected do.
        'expected ',(integer #expected),' arguments, got ',integer #arguments return.
    end.
    for_i. i.#arguments do.
        argument =. i{::arguments
        index =. names i.<argument
        if. index=#names do.
            'unknown ',noun,' ',argument return.
        end.
        kind =. i{::expected
        if. -. (index{::types)subtype kind do.
            'argument ',(integer i+1),' (',argument,') is not of type ',kind return.
        end.
    end.
    ''
)
validate_domain =: 3 : 0
    kept =. 0$a:
    DomainDiagnostics =: 0$a:
    for_schema. Schemas do.
        schema =. >schema
        'name parameters condition effects cost' =. schema
        'names types' =. parameters
        error =. ''
        for_type. types do.
            if. -.type e.TypeNames do.
                error =. 'unknown type ',>type
                break.
            end.
        end.
        if. 0=#error do.
            for_literal. condition,effects do.
                atom =. 1{::>literal
                'predicate arguments' =. atom
                if. predicate-:,'=' do.
                    expected =. 2$<'object'
                else.
                    index =. PredicateNames i.<predicate
                    if. index=#PredicateNames do.
                        error =. 'unknown predicate ',predicate
                    else.
                        expected =. index{::PredicateTypes
                    end.
                end.
                if. 0=#error do.
                    fields =. (<arguments),(<expected),(<names),(<types),<'variable'
                    error =. argument_error fields
                end.
                if. #error do.
                    error =. (notation atom),': ',error
                    break.
                end.
            end.
        end.
        if. #error do.
            DomainDiagnostics =: DomainDiagnostics,<'error: action ',name,': ',error
        else.
            kept =. kept,<schema
        end.
    end.
    Schemas =: kept
    SchemaNames =: 0$a:
    used =. 0$a:
    for_schema. Schemas do.
        schema =. >schema
        SchemaNames =: SchemaNames,<0{::schema
        for_literal. (2{::schema),3{::schema do.
            atom =. 1{::>literal
            used =. used,0{atom
        end.
    end.
    for_predicate. PredicateNames do.
        if. -.predicate e.used do.
            DomainDiagnostics =: DomainDiagnostics,<'warning: predicate ',(>predicate),' is not used by any action'
        end.
    end.
    classify_predicates ''
)
validate_problem =: 3 : 0
    'name objects types initial goals' =. y
    sides =. (<initial),<goals
    diagnostics =. 0$a:
    result =. 3{.y
    for_side. i.2 do.
        kept =. 0$a:
        label =. 'init'
        if. side do.
            label =. 'goal'
        end.
        for_atom. side{::sides do.
            atom =. >atom
            'predicate arguments' =. atom
            index =. PredicateNames i.<predicate
            error =. ''
            if. index=#PredicateNames do.
                error =. 'unknown predicate ',predicate
            else.
                fields =. (<arguments),(index{PredicateTypes),(<objects),(<types),<'object'
                error =. argument_error fields
            end.
            if. (0=#error)*.(<atom)e.kept do.
                error =. 'duplicate'
            end.
            if. #error do.
                diagnostics =. diagnostics,<'warning: ',label,' ',(notation atom),': ',error
            else.
                kept =. kept,<atom
            end.
        end.
        result =. result,<kept
    end.
    result,<diagnostics
)
activate_problem =: 3 : 0
    ActiveProblem =: y
    ActiveSource =: 0{::y
    GroundFacts =: 4{::y
    GroundActions =: 5{::y
    InitialState =: 6{::y
    GoalFacts =: 7{::y
)
action_text =: 3 : 0
    action =. y{::GroundActions
    source =. (0{::action){::Schemas
    notation (0{source),1{action
)
plan_cost =: 3 : 0
    total =. 0
    for_number. y do.
        total =. total+2{::number{::GroundActions
    end.
    total
)
plan_steps =: 3 : 0
    steps =. 0$a:
    for_number. y do.
        action =. number{::GroundActions
        schema =. (0{::action){::Schemas
        steps =. steps,<(0{schema),1{action
    end.
    steps
)
validate_steps =: 3 : 0
    steps =. y
    world =. 3{::ActiveSource
    objects =. 1{::ActiveSource
    types =. 2{::ActiveSource
    cost =. 0
    for_i. i.#steps do.
        step =. i{::steps
        'name arguments' =. step
        heading =. 'step ',(integer i+1),' ',(notation step),': '
        index =. SchemaNames i.<name
        if. index=#SchemaNames do.
            message =. heading,'unknown action ',name
            (<'invalid'),(<,<message),<i return.
        end.
        'schema_name parameters condition effects action_cost' =. index{::Schemas
        'names expected' =. parameters
        fields =. (<arguments),(<expected),(<objects),(<types),<'object'
        error =. argument_error fields
        if. #error do.
            (<'invalid'),(<,<heading,error),<i return.
        end.
        binding =. (<names),<arguments
        for_literal. condition do.
            'sign atom' =. >literal
            bound =. binding substitute atom
            if. (0{::bound)-:,'=' do.
                terms =. 1{::bound
                truth =. (0{::terms)-:1{::terms
            else.
                truth =. (<bound)e.world
            end.
            if. truth~:sign do.
                text =. notation bound
                if. -.sign do.
                    text =. '(not ',text,')'
                end.
                message =. heading,'precondition ',text,' is false'
                (<'invalid'),(<,<message),<i return.
            end.
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
        world =. ~.(world-.deletes),adds
        cost =. cost+action_cost
    end.
    messages =. 0$a:
    for_atom. 4{::ActiveSource do.
        if. -.atom e.world do.
            messages =. messages,<'unsatisfied goal ',notation >atom
        end.
    end.
    if. #messages do.
        (<'goal not reached'),(<messages),<#steps
    else.
        message =. 'length=',(integer #steps),' cost=',integer cost
        (<'valid'),(<,<message),<#steps
    end.
)
verdict =: 3 : 0
    status =. 0{::y
    separator =. ': '
    if. status-:'valid' do.
        separator =. ' '
    end.
    status,separator,0{::1{::y
)
interferes =: 4 : 0
    a =. +./(6{::x)*.(3{::y)+.5{::y
    b =. +./(6{::y)*.(3{::x)+.5{::x
    c =. +./(5{::x)*.4{::y
    d =. +./(5{::y)*.4{::x
    a+.b+.c+.d
)
parallelize =: 3 : 0
    assigned =. i.0
    layers =. 0$a:
    for_position. i.#y do.
        action =. (position{y){::GroundActions
        layer =. 1
        for_earlier. i.position do.
            previous =. (earlier{y){::GroundActions
            dependency =. (+./(5{::previous)*.3{::action)+.(+./(6{::previous)*.4{::action)
            if. dependency+.previous interferes action do.
                layer =. layer>.1+earlier{assigned
            end.
        end.
        assigned =. assigned,layer
        while. (#layers)<layer do.
            layers =. layers,<i.0
        end.
        index =. layer-1
        layers =. (<(index{::layers),position{y)index}layers
    end.
    layers
)
validate_parallel =: 3 : 0
    state =. InitialState
    for_position. i.#y do.
        layer =. position{::y
        for_number. layer do.
            if. -. (number{::GroundActions)action_applicable state do.
                'invalid at layer ',integer position+1 return.
            end.
        end.
        for_i. i.#layer do.
            first =. (i{layer){::GroundActions
            for_number. (i+1)}.layer do.
                if. first interferes number{::GroundActions do.
                    'invalid at layer ',integer position+1 return.
                end.
            end.
        end.
        deletes =. (#state)$0
        adds =. (#state)$0
        for_number. layer do.
            action =. number{::GroundActions
            deletes =. deletes+.6{::action
            adds =. adds+.5{::action
        end.
        state =. (state*.-.deletes)+.adds
    end.
    if. */GoalFacts<:state do. 'valid' else. 'goal not reached' end.
)
improve_plan =: 3 : 0
    sequence =. y
    position =. 0
    while. position<#sequence do.
        state =. InitialState
        for_number. position{.sequence do.
            state =. (number{::GroundActions)apply_action state
        end.
        applied =. i.0
        for_number. (position+1)}.sequence do.
            action =. number{::GroundActions
            if. action action_applicable state do.
                state =. action apply_action state
                applied =. applied,number
            end.
        end.
        if. */GoalFacts<:state do.
            sequence =. (position{.sequence),applied
        else.
            position =. position+1
        end.
    end.
    sequence
)
transform_negatives =: 3 : 0
    negatives =. (#GroundFacts)$0
    for_action. GroundActions do.
        negatives =. negatives+.4{::>action
    end.
    original =. #GroundFacts
    negative_facts =. I.negatives
    count =. #negative_facts
    complement =. original+i.count
    initial =. InitialState,-.negative_facts{InitialState
    goal =. GoalFacts,count$0
    actions =. 0$a:
    for_number. i.#GroundActions do.
        action =. number{::GroundActions
        pre =. (3{::action),negative_facts{4{::action
        add =. (5{::action),negative_facts{6{::action
        delete =. (6{::action),negative_facts{5{::action
        actions =. actions,<( <number),(<pre),(<add),<delete
    end.
    (<actions),(<initial),(<goal),<count
)
action_texts =: 3 : 0
    items =. 0$a:
    for_number. y do.
        items =. items,<action_text number
    end.
    items
)
domain_report =: 3 : 0
    GroundingLines =: (<'== domain ',DomainName,' =='),DomainDiagnostics
    for_type. TypeNames do.
        current =. >type
        chain =. 0$a:
        while. #current do.
            chain =. chain,<current
            current =. (TypeNames i.<current){::TypeParents
        end.
        GroundingLines =: GroundingLines,<'type ',' < 'join chain
    end.
    for_i. i.#PredicateNames do.
        kind =. 'static'
        if. i{FluentPredicates do.
            kind =. 'fluent'
        end.
        line =. 'predicate ',(i{::PredicateNames),'/',(integer #i{::PredicateTypes),' ',kind
        GroundingLines =: GroundingLines,<line
    end.
    for_schema. Schemas do.
        'name parameters condition effects cost' =. >schema
        adds =. 0
        for_literal. effects do.
            adds =. adds+0{::>literal
        end.
        line =. 'action ',name,'/',(integer #0{::parameters),' cost=',integer cost
        line =. line,' pre=',(integer #condition),' add=',integer adds
        GroundingLines =: GroundingLines,<line,' del=',integer (#effects)-adds
    end.
)
grounding_report =: 3 : 0
    'source by_type statistics candidates facts actions initial goal unreachable static_count' =. ActiveProblem
    name =. 0{::source
    lines =. (<''),(<'== problem ',name,' =='),5{::source
    lines =. lines,<'objects: ',integer #1{::source
    for_i. i.#TypeNames do.
        lines =. lines,<('  ',(i{::TypeNames),':')headed i{::by_type
    end.
    lines =. lines,<'static facts: ',integer static_count
    for_i. i.#Schemas do.
        'assignments candidate_count reachable' =. i{statistics
        line =. 'schema ',(i{::SchemaNames),': assignments=',integer assignments
        lines =. lines,<line,' candidates=',(integer candidate_count),' reachable=',integer reachable
    end.
    lines =. lines,<'candidates: ',(integer candidates),' reachable: ',integer #actions
    line =. 'facts: ',(integer #facts),' init: ',integer +/initial
    lines =. lines,<line,' goals: ',integer +/goal
    for_atom. unreachable do.
        lines =. lines,<'unreachable goal: ',notation >atom
    end.
    items =. 0$a:
    for_i. I.FluentPredicates do.
        count =. 0
        for_atom. facts do.
            count =. count+(i{::PredicateNames)-:0{::>atom
        end.
        items =. items,<(i{::PredicateNames),'=',integer count
    end.
    lines =. lines,<'facts by predicate:'headed items
    lines =. lines,<'facts:'
    for_i. i.#facts do.
        lines =. lines,<'  ',(integer i),' ',notation i{::facts
    end.
    lines =. lines,<'actions:'
    for_i. i.#actions do.
        action =. i{::actions
        line =. '  ',(integer i),' ',(action_text i),' cost=',integer 2{::action
        line =. line,' pre=',(number_list 3{::action),' neg=',number_list 4{::action
        lines =. lines,<line,' add=',(number_list 5{::action),' del=',number_list 6{::action
    end.
    GroundingLines =: GroundingLines,lines
)
initial_report =: 3 : 0
    values =. heuristic_values InitialState
    InitialLandmarks =: landmarks InitialState
    if. InitialLandmarks-:,_1 do.
        InitialLandmarks =: i.0
    end.
    relaxed =. relaxed_plan InitialState
    if. relaxed-:,_1 do.
        relaxed =. i.0
    end.
    PlanLines =: PlanLines,<'initial h: ',heuristic_text values
    PlanLines =: PlanLines,<'landmarks: ',integer #InitialLandmarks
    for_fact. InitialLandmarks do.
        PlanLines =: PlanLines,<'  ',notation fact{::GroundFacts
    end.
    line =. 'relaxed plan: length=',(integer #relaxed),' cost=',value_text 3{values
    PlanLines =: PlanLines,<line
    for_number. relaxed do.
        PlanLines =: PlanLines,<'  ',action_text number
    end.
    PlanLines =: PlanLines,<'helpful:'headed action_texts helpful_actions InitialState
)
plan_report =: 4 : 0
    tag =. x
    plan =. y
    cost =. plan_cost plan
    line =. 'plan: length=',(integer #plan),' cost=',integer cost
    index =. EarlierPlans i.<plan
    if. index<#EarlierPlans do.
        line =. line,' (same as ',(index{::EarlierTags),')'
    else.
        EarlierPlans =: EarlierPlans,<plan
        EarlierTags =: EarlierTags,<tag
    end.
    PlanLines =: PlanLines,<line
    for_i. i.#plan do.
        PlanLines =: PlanLines,<'  ',(integer i+1),' ',action_text i{plan
    end.
    counts =. (#Schemas)$0
    for_number. plan do.
        source =. 0{::number{::GroundActions
        counts =. (1+source{counts)source}counts
    end.
    items =. 0$a:
    for_i. I.counts>0 do.
        items =. items,<(i{::SchemaNames),'=',integer i{counts
    end.
    PlanLines =: PlanLines,<'schemas:'headed items
    layers =. parallelize plan
    PlanLines =: PlanLines,<'parallel: layers=',integer #layers
    for_i. i.#layers do.
        PlanLines =: PlanLines,<('  ',(integer i+1),':')headed action_texts i{::layers
    end.
    improved =. improve_plan plan
    removed =. (#plan)-#improved
    line =. 'improved: length=',(integer #improved),' cost=',integer plan_cost improved
    PlanLines =: PlanLines,<line,' removed=',integer removed
    if. removed do.
        for_i. i.#improved do.
            PlanLines =: PlanLines,<'  ',(integer i+1),' ',action_text i{improved
        end.
    end.
    mask =. (#GroundFacts)$0
    mask =. 1 InitialLandmarks}mask
    reached =. (#GroundFacts)$0
    state =. InitialState
    for_number. plan do.
        state =. (number{::GroundActions)apply_action state
        reached =. reached+.state*.mask
    end.
    PlanLines =: PlanLines,<'landmarks reached: ',(integer +/reached),'/',integer #InitialLandmarks
    for_fact. I.mask*.-.reached do.
        PlanLines =: PlanLines,<'  missed ',notation fact{::GroundFacts
    end.
    checked =. validate_steps plan_steps plan
    checked_improved =. validate_steps plan_steps improved
    ValidationLines =: ValidationLines,<tag,': ',verdict checked
    ValidationLines =: ValidationLines,<'  parallel: ',validate_parallel layers
    ValidationLines =: ValidationLines,<'  improved: ',verdict checked_improved
    ValidatedPlans =: ValidatedPlans+1
    ValidPlans =: ValidPlans+('valid'-:0{::checked)
)
search_result_report =: 4 : 0
    tag =. x
    outcome =. y
    PlanLines =: PlanLines,<'-- ',tag,' --'
    if. #8{::ActiveProblem do.
        PlanLines =: PlanLines,<'result: FAIL (unreachable goal)'
        i.0 return.
    end.
    'status expanded generated plan' =. 4{.outcome
    state =. 'solved'
    if. -.status-:'solved' do.
        state =. 'FAIL (',status,')'
    end.
    line =. 'result: ',state,' expanded=',(integer expanded),' generated=',integer generated
    PlanLines =: PlanLines,<line
    if. status-:'solved' do.
        tag plan_report plan
    end.
)
graph_report =: 4 : 0
    complements =. x
    outcome =. y
    if. #8{::ActiveProblem do.
        GraphLines =: GraphLines,<'result: FAIL (unreachable goal)'
        i.0 return.
    end.
    'status searched tried plan layers lines memo_hits' =. outcome
    GraphLines =: GraphLines,(<'complementary facts: ',integer complements),lines
    counts =. ' searched=',(integer searched),' memo_hits=',(integer memo_hits),' tried=',integer tried
    if. status-:'solved' do.
        line =. 'result: solved levels=',(integer #layers),' length=',integer #plan
        GraphLines =: GraphLines,<line,' cost=',(integer plan_cost plan),counts
        for_i. i.#layers do.
            GraphLines =: GraphLines,<('layer ',(integer i+1),':')headed action_texts i{::layers
        end.
    else.
        GraphLines =: GraphLines,<'result: FAIL (',status,')',counts
    end.
)
profile_report =: 4 : 0
    tag =. x
    plan =. y
    state =. InitialState
    remaining =. plan_cost plan
    overestimates =. 5$0
    PlanLines =: PlanLines,<'-- profile (',tag,') --'
    for_i. i.1+#plan do.
        values =. heuristic_values state
        line =. '  ',(integer i),': h*=',(integer remaining),' ',heuristic_text values
        PlanLines =: PlanLines,<line
        overestimates =. overestimates+(values=_1)+.values>remaining
        if. i<#plan do.
            action =. (i{plan){::GroundActions
            state =. action apply_action state
            remaining =. remaining-2{::action
        end.
    end.
    PlanLines =: PlanLines,<'overestimates: ',heuristic_text overestimates
    PlanLines =: PlanLines,<'-- causal links (',tag,') --'
    suppliers =. (#GroundFacts)$0
    for_i. i.#plan do.
        number =. i{plan
        action =. number{::GroundActions
        items =. 0$a:
        for_fact. I.3{::action do.
            items =. items,<(notation fact{::GroundFacts),'<-',integer fact{suppliers
        end.
        heading =. '  ',(integer i+1),' ',(action_text number),':'
        PlanLines =: PlanLines,<heading headed items
        suppliers =. (i+1)(I.5{::action)}suppliers
    end.
    items =. 0$a:
    for_fact. I.GoalFacts do.
        items =. items,<(notation fact{::GroundFacts),'<-',integer fact{suppliers
    end.
    PlanLines =: PlanLines,<'  goal:'headed items
)
summarize_problem =: 4 : 0
    proof =. x
    outcomes =. y
    costs =. (#outcomes)$_1
    solved =. 0
    for_i. i.#outcomes do.
        outcome =. i{::outcomes
        if. 'solved'-:0{::outcome do.
            solved =. solved+1
            costs =. (plan_cost 3{::outcome)i}costs
        end.
    end.
    best =. _1
    possible =. costs#~costs~:_1
    if. #possible do.
        best =. <./possible
    end.
    optimal =. 'unknown'
    if. proof~:_1 do.
        optimal =. integer proof{costs
    else.
        failures =. ('unreachable goal';'dead end';'exhausted';'unreachable')
        for_outcome. outcomes do.
            if. (0{>outcome)e.failures do.
                optimal =. 'none'
                break.
            end.
        end.
    end.
    pairs =. RunPairs,<;:'graphplan none'
    name =. 0{::ActiveSource
    for_i. i.#outcomes do.
        outcome =. i{::outcomes
        'algorithm heuristic' =. i{::pairs
        expanded =. 1{::outcome
        generated =. 2{::outcome
        length =. '-'
        cost =. '-'
        is_solved =. 'solved'-:0{::outcome
        is_best =. 0
        if. is_solved do.
            length =. integer #3{::outcome
            cost =. integer i{costs
            is_best =. best=i{costs
        end.
        TagTotals =: ((i{TagTotals)+is_solved,is_best,expanded,generated)i}TagTotals
        fields =. (<name),(<algorithm),(<heuristic),(<length),(<cost),(<integer expanded),<integer generated
        ComparisonLines =: ComparisonLines,<','join fields
    end.
    (<solved),(<best),<optimal
)
solve_problem =: 3 : 0
    source =. validate_problem y
    problem =. ground_problem source
    AllProblems =: AllProblems,<problem
    GroundProblemNames =: GroundProblemNames,<0{::source
    activate_problem problem
    grounding_report ''
    heading =. '== problem ',(0{::source),' =='
    PlanLines =: PlanLines,<heading
    GraphLines =: GraphLines,<heading
    ValidationLines =: ValidationLines,<heading
    outcomes =. 0$a:
    EarlierPlans =: 0$a:
    EarlierTags =: 0$a:
    proof =. _1
    unreachable =. 0<#8{::problem
    if. unreachable do.
        PlanLines =: PlanLines,<'initial h: unreachable goal'
        InitialLandmarks =: i.0
    else.
        init_heuristics problem
        initial_report ''
    end.
    for_i. i.#RunPairs do.
        'algorithm heuristic' =. i{::RunPairs
        if. unreachable do.
            outcome =. (<'unreachable goal'),(<0),(<0),<i.0
        else.
            arguments =. (<InitialState),(<algorithm),(<heuristic),(<Budget),<Weight
            outcome =. search_run arguments
        end.
        outcomes =. outcomes,<outcome
        tag =. i{::Tags
        tag search_result_report outcome
        if. (proof=_1)*.('solved'-:0{::outcome)*.((tag-:'ucs none')+.tag-:'astar hmax') do.
            proof =. i
        end.
    end.
    complements =. 0
    if. unreachable do.
        graph =. (<'unreachable goal'),(<0),(<0),<i.0
    else.
        'actions initial goal complements' =. transform_negatives ''
        graph =. graphplan_run(<actions),(<initial),(<goal),<LevelLimit
    end.
    outcomes =. outcomes,<graph
    'graphplan'search_result_report graph
    complements graph_report graph
    if. proof~:_1 do.
        (proof{::Tags)profile_report 3{::proof{::outcomes
    end.
    summary =. proof summarize_problem outcomes
    Summaries =: Summaries,<summary
    PlanLines =: PlanLines,<''
    GraphLines =: GraphLines,<''
    ValidationLines =: ValidationLines,<''
)
summary_report =: 3 : 0
    PlanLines =: PlanLines,<'== summary =='
    for_i. i.#Summaries do.
        'solved best optimal' =. i{::Summaries
        best_text =. '-'
        if. best~:_1 do.
            best_text =. integer best
        end.
        line =. (i{::GroundProblemNames),': solved=',(integer solved),'/',integer #Tags
        PlanLines =: PlanLines,<line,' best=',best_text,' optimal=',optimal
    end.
    for_i. i.#Tags do.
        'solved best expanded generated' =. i{TagTotals
        line =. (i{::Tags),': solved=',(integer solved),' best=',integer best
        PlanLines =: PlanLines,<line,' expanded=',(integer expanded),' generated=',integer generated
    end.
)
mapped_steps =: 3 : '(plan_steps i.#GroundActions)i.y'
repair_candidate =: 4 : 0
    checked =. x
    steps =. y
    if. #8{::ActiveProblem do.
        ValidationLines =: ValidationLines,<'  repair: FAIL (unreachable goal)'
        i.0 return.
    end.
    prefix =. mapped_steps (2{::checked){.steps
    state =. InitialState
    for_number. prefix do.
        state =. (number{::GroundActions)apply_action state
    end.
    'algorithm heuristic' =. RepairPair
    arguments =. (<state),(<algorithm),(<heuristic),(<Budget),<Weight
    outcome =. search_run arguments
    if. -.'solved'-:0{::outcome do.
        ValidationLines =: ValidationLines,<'  repair: FAIL (',(0{::outcome),')'
        i.0 return.
    end.
    suffix =. 3{::outcome
    repaired =. prefix,suffix
    validation =. validate_steps plan_steps repaired
    line =. '  repair: kept=',(integer #prefix),' added=',integer #suffix
    ValidationLines =: ValidationLines,<line,' ',verdict validation
    for_i. i.#repaired do.
        ValidationLines =: ValidationLines,<'    ',(integer i+1),' ',action_text i{repaired
    end.
)
candidate_report =: 3 : 0
    ValidationLines =: ValidationLines,<'== candidates =='
    ValidCandidates =: 0
    for_candidate. Candidates do.
        'number name label steps' =. >candidate
        index =. GroundProblemNames i.<name
        problem =. index{::AllProblems
        activate_problem problem
        if. 0=#8{::problem do.
            init_heuristics problem
        end.
        checked =. validate_steps steps
        heading =. 'candidate ',(integer number),' ',name,' ',label,': '
        if. 'valid'-:0{::checked do.
            ValidCandidates =: ValidCandidates+1
            ValidationLines =: ValidationLines,<heading,verdict checked
            mapped =. mapped_steps steps
            improved =. improve_plan mapped
            best =. 1{::index{::Summaries
            best_text =. '-'
            if. best~:_1 do.
                best_text =. integer best
            end.
            line =. '  improved: length=',(integer #improved),' cost=',integer plan_cost improved
            line =. line,' removed=',(integer (#mapped)-#improved),' best known=',best_text
            ValidationLines =: ValidationLines,<line
        else.
            ValidationLines =: ValidationLines,<heading,0{::checked
            for_message. 1{::checked do.
                ValidationLines =: ValidationLines,<'  ',>message
            end.
            checked repair_candidate steps
        end.
    end.
    ValidationLines =: ValidationLines,(<''),<'== summary =='
    ValidationLines =: ValidationLines,<'plans: ',(integer ValidatedPlans),' valid: ',integer ValidPlans
    ValidationLines =: ValidationLines,<'candidates: ',(integer #Candidates),' valid: ',integer ValidCandidates
)
write_lines =: 4 : '((LF join y),LF)1!:2 <''output/'',x'
run =: 3 : 0
    read_domain 1!:1 <'input/domain.txt'
    read_problems 1!:1 <'input/problems.txt'
    read_settings ''
    read_candidates ''
    validate_domain ''
    PlanLines =: 0$a:
    GraphLines =: 0$a:
    ValidationLines =: 0$a:
    ComparisonLines =: <'problem,algorithm,heuristic,length,cost,expanded,generated'
    AllProblems =: 0$a:
    GroundProblemNames =: 0$a:
    Summaries =: 0$a:
    TagTotals =: ((#Tags),4)$0
    ValidatedPlans =: 0
    ValidPlans =: 0
    domain_report ''
    for_source. SourceProblems do.
        solve_problem >source
    end.
    summary_report ''
    candidate_report ''
    try.
        1!:5 <'output'
    catch.
    end.
    'grounding.txt'write_lines GroundingLines
    'plans.txt'write_lines PlanLines
    'graphplan.txt'write_lines GraphLines
    'validation.txt'write_lines ValidationLines
    'comparison.csv'write_lines ComparisonLines
)
run ''
