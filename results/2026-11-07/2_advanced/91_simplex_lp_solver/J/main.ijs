ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'rational.ijs'
load SourceDirectory,'lp_parser.ijs'
load SourceDirectory,'tableau.ijs'
load SourceDirectory,'simplex.ijs'
load SourceDirectory,'branch_bound.ijs'

join =: 4 : 0
    text =. ''
    for_i. i.#y do.
        if. i do. text =. text,x end.
        text =. text,i{::y
    end.
    text
)
word =: 3 : 0
    if. 2=3!:0 y do. ,y else. fraction y end.
)
emit =: 3 : ''' ''join word&.>y'
dot =: 4 : '+/x*y'
coefficients =: 4 : 0
    values =. (#x)$0x
    for_term. y do.
        'name coefficient' =. >term
        index =. x i.<name
        values =. ((index{values)+coefficient)index}values
    end.
    values
)
content_check =: 3 : 0
    'name error direction objective constraints bounds integers binaries' =. y
    if. #error do. (<0$a:),<error return. end.
    variables =. 0$a:
    expressions =. ,<objective
    for_constraint. constraints do. expressions =. expressions,<2{::>constraint end.
    for_expression. expressions do.
        for_term. >expression do.
            variable =. 0{::>term
            if. -.(<variable)e.variables do. variables =. variables,<variable end.
        end.
    end.
    costs =. variables coefficients objective
    matrix =. (0,#variables)$0x
    rhs =. 0$0x
    comparisons =. names =. 0$a:
    for_constraint. constraints do.
        'line constraint_name terms comparison value' =. >constraint
        if. (<constraint_name)e.names do.
            error =. (<line),<'duplicate constraint ',constraint_name
            (<0$a:),<error return.
        end.
        names =. names,<constraint_name
        matrix =. matrix,variables coefficients terms
        rhs =. rhs,value
        comparisons =. comparisons,<comparison
    end.
    lower =. (#variables)$<0x
    upper =. (#variables)$<''
    integer_flags =. (#variables)$0
    for_bound. bounds do.
        'line variable kind low high' =. >bound
        index =. variables i.<variable
        if. index=#variables do.
            error =. (<line),<'unknown variable ',variable
            (<0$a:),<error return.
        end.
        if. (<kind)e.'lower';'both' do. lower =. (<low)index}lower end.
        if. (<kind)e.'upper';'both' do. upper =. (<high)index}upper end.
        low =. index{::lower
        high =. index{::upper
        if. (finite low)*.finite high do.
            if. low>high do.
                error =. (<line),<'inconsistent bounds ',variable
                (<0$a:),<error return.
            end.
        end.
    end.
    for_declaration. integers do.
        'line declarations' =. >declaration
        for_variable. declarations do.
            variable =. >variable
            index =. variables i.<variable
            if. index=#variables do.
                error =. (<line),<'unknown variable ',variable
                (<0$a:),<error return.
            end.
            integer_flags =. 1 index}integer_flags
            low =. index{::lower
            high =. index{::upper
            if. finite low do. low =. >.low end.
            if. finite high do. high =. <.high end.
            lower =. (<low)index}lower
            upper =. (<high)index}upper
            if. (finite low)*.finite high do.
                if. low>high do.
                    error =. (<line),<'inconsistent bounds ',variable
                    (<0$a:),<error return.
                end.
            end.
        end.
    end.
    for_declaration. binaries do.
        'line declarations' =. >declaration
        for_variable. declarations do.
            variable =. >variable
            index =. variables i.<variable
            if. index=#variables do.
                error =. (<line),<'unknown variable ',variable
                (<0$a:),<error return.
            end.
            integer_flags =. 1 index}integer_flags
            lower =. (<0x)index}lower
            upper =. (<1x)index}upper
        end.
    end.
    model =. (<name),(<direction),(<variables),(<costs),(<matrix),(<rhs),(<comparisons),(<names)
    model =. model,(<lower),(<upper),<integer_flags
    (<model),<0$a:
)
set_model =: 3 : 0
    'ModelName ModelDirection ModelVariables ModelCosts ModelMatrix ModelRhs ModelComparisons' =: 7{.y
    'ConstraintNames ModelLower ModelUpper ModelInteger' =: 7}.y
)
standard_form =: 3 : 0
    'lower upper' =. y
    column_names =. mappings =. 0$a:
    owners =. directions =. i.0
    offsets =. 0$0x
    for_j. i.#ModelVariables do.
        name =. j{::ModelVariables
        low =. j{::lower
        high =. j{::upper
        first =. #column_names
        if. finite low do.
            kind =. 'shift'
            offset =. low
            columns =. ,first
            signs =. ,1
            names =. ,<name
        elseif. finite high do.
            kind =. 'reflect'
            offset =. high
            columns =. ,first
            signs =. ,_1
            names =. ,<name,39{a.
        else.
            kind =. 'split'
            offset =. 0x
            columns =. first,first+1
            signs =. 1 _1
            names =. (<name,'+'),<name,'-'
        end.
        column_names =. column_names,names
        owners =. owners,(#columns)$j
        directions =. directions,signs
        offsets =. offsets,offset
        mappings =. mappings,<(<kind),(<offset),(<columns),(<signs),<_1
    end.
    row_names =. ConstraintNames
    matrix =. (0,#column_names)$0x
    rhs =. 0$0x
    comparisons =. ModelComparisons
    for_i. i.#ModelRhs do.
        row =. i{ModelMatrix
        matrix =. matrix,directions*owners{row
        rhs =. rhs,(i{ModelRhs)-row dot offsets
    end.
    for_j. i.#mappings do.
        'kind offset columns signs upper_row' =. j{::mappings
        if. (kind-:'shift')*.finite j{::upper do.
            mapping =. j{::mappings
            mapping =. (<#row_names)4}mapping
            mappings =. (<mapping)j}mappings
            row_names =. row_names,<(j{::ModelVariables),'.ub'
            row =. (#column_names)$0x
            row =. 1x({.columns)}row
            matrix =. matrix,row
            rhs =. rhs,(j{::upper)-j{::lower
            comparisons =. comparisons,<'<='
        end.
    end.
    row_signs =. (#row_names)$1
    for_i. i.#rhs do.
        if. (i{rhs)<0 do.
            matrix =. (-i{matrix)i}matrix
            rhs =. (-i{rhs)i}rhs
            row_signs =. _1 i}row_signs
            comparison =. i{::comparisons
            if. comparison-:'<=' do. comparison =. '>='
            elseif. comparison-:'>=' do. comparison =. '<=' end.
            comparisons =. (<comparison)i}comparisons
        end.
    end.
    slack =. initial =. (#row_names)$_1
    artificial =. (#column_names)$0
    for_i. i.#row_names do.
        comparison =. i{::comparisons
        if. comparison-:,'=' do. continue. end.
        column =. #column_names
        slack =. column i}slack
        column_names =. column_names,<'s:',i{::row_names
        values =. (#row_names)$0x
        sign =. _1x
        if. comparison-:'<=' do.
            sign =. 1x
            initial =. column i}initial
        end.
        matrix =. matrix,.sign i}values
        artificial =. artificial,0
    end.
    for_i. i.#row_names do.
        if. '<='-:i{::comparisons do. continue. end.
        column =. #column_names
        initial =. column i}initial
        column_names =. column_names,<'a:',i{::row_names
        values =. (#row_names)$0x
        matrix =. matrix,.1x i}values
        artificial =. artificial,1
    end.
    direction =. 1
    if. ModelDirection-:'maximize' do. direction =. _1 end.
    phase2 =. direction*directions*owners{ModelCosts
    phase2 =. phase2,((#column_names)-#phase2)$0x
    phase1 =. x:artificial
    constant =. ModelCosts dot offsets
    form =. (<column_names),(<row_names),(<mappings),(<matrix),(<rhs),(<row_signs),(<slack)
    form,(<artificial),(<initial),(<phase1),(<phase2),(<constant),<direction
)
load_form =: 3 : 0
    'ColumnNames RowNames Mappings InitialMatrix InitialRhs RowSigns SlackColumns' =: 7{.y
    'Artificial InitialBasis Phase1Costs Phase2Costs ObjectiveConstant DirectionSign' =: 7}.y
)
display_value =: 4 : 0
    if. x=1 do. y else. ObjectiveConstant+DirectionSign*y end.
)
emit_log =: 4 : 0
    if. x<:LogLevel do. LogLines =: LogLines,<y end.
)
display_log =: 4 : 0
    if. LogLevel>:2 do. LogLines =: LogLines,x tableau_display y end.
)
tableau_solution =: 3 : 0
    values =. (#ColumnNames)$0x
    values =. TBeta TBasis}values
    solution =. 0$0x
    for_mapping. Mappings do.
        'kind offset columns signs upper_row' =. >mapping
        solution =. solution,offset+signs dot columns{values
    end.
    solution
)
solve_lp =: 3 : 0
    'lower upper number level' =. y
    LogLevel =: level
    form =. standard_form(<lower),<upper
    load_form form
    restore_tableau(<InitialMatrix),(<InitialRhs),<InitialBasis
    LogLines =: 0$a:
    0 emit_log emit 'SOLVE node';number;'rows';(#RowNames);'columns';(#ColumnNames);'artificials';+/Artificial
    for_j. i.#Mappings do.
        'kind offset columns signs upper_row' =. j{::Mappings
        text =. 'MAP ',(j{::ModelVariables),' ',kind
        if. -.kind-:'split' do. text =. text,' ',fraction offset end.
        if. (kind-:'shift')*.finite j{::upper do. text =. text,' upper ',fraction j{::upper end.
        1 emit_log text
    end.
    for_i. I.RowSigns=_1 do. 1 emit_log 'FLIP ',i{::RowNames end.
    p1 =. p2 =. drives =. redundant =. 0
    w =. 0x
    status =. 'OPTIMAL'
    unbounded =. _1
    if. +./Artificial do.
        1 emit_log 'PHASE 1'
        'phase 1 start'display_log(<Phase1Costs),<1
        'p1 unused logs' =. run_phase(<Phase1Costs),(<i.#ColumnNames),<1
        if. LogLevel>:1 do. LogLines =: LogLines,logs end.
        w =. phase_value Phase1Costs
        1 emit_log emit 'PHASE 1 END objective';w;'iterations';p1
        if. w>0 do.
            status =. 'INFEASIBLE'
            'final'display_log(<Phase1Costs),<1
        else.
            for_i. i.#TBeta do.
                basic =. i{TBasis
                if. -.basic{Artificial do. continue. end.
                candidates =. I.(-.Artificial)*.0~:i{TMatrix
                if. 0=#candidates do.
                    redundant =. redundant+1
                    1 emit_log 'REDUNDANT row ',i{::RowNames
                else.
                    entering =. {.candidates
                    leaving =. basic{::ColumnNames
                    pivot i,entering
                    drives =. drives+1
                    1 emit_log emit 'DRIVE row';(i{::RowNames);'enter';(entering{::ColumnNames);'leave';leaving
                end.
            end.
        end.
    end.
    if. -.status-:'INFEASIBLE' do.
        1 emit_log 'PHASE 2'
        'phase 2 start'display_log(<Phase2Costs),<2
        'p2 unbounded logs' =. run_phase(<Phase2Costs),(<I.-.Artificial),<2
        if. LogLevel>:1 do. LogLines =: LogLines,logs end.
        if. unbounded~:_1 do.
            status =. 'UNBOUNDED'
            1 emit_log 'UNBOUNDED enter ',unbounded{::ColumnNames
        end.
        value =. 2 display_value phase_value Phase2Costs
        1 emit_log emit 'PHASE 2 END objective';value;'iterations';p2
        'final'display_log(<Phase2Costs),<2
    end.
    objective =. ''
    if. status-:'OPTIMAL' do. objective =. 2 display_value phase_value Phase2Costs end.
    text =. emit 'RESULT';status;'objective';(fraction objective);'phase1';p1;'phase2';p2;'drives';drives;'redundant';redundant
    0 emit_log text
    solution =. tableau_solution ''
    tableau =. (<TMatrix),(<TBeta),<TBasis
    counts =. p1;p2;drives;redundant;(p1+p2+drives)
    (<status),(<objective),(<solution),(<form),(<tableau),(<unbounded),(<w),counts,<LogLines
)
restore_lp =: 3 : 0
    load_form 3{::y
    restore_tableau 4{::y
)
farkas =: 3 : 'RowSigns*((InitialBasis{Phase1Costs)-InitialBasis{reduced_costs Phase1Costs)'
unbounded_ray =: 3 : 0
    column =. 5{::y
    delta =. (#ColumnNames)$0x
    delta =. 1x column}delta
    delta =. (-column{"1 TMatrix)TBasis}delta
    ray =. 0$0x
    for_mapping. Mappings do.
        'kind offset columns signs upper_row' =. >mapping
        ray =. ray,signs dot columns{delta
    end.
    (<ray),<ModelCosts dot ray
)

statistics_line =: 3 : 0
    matrix =. ,ModelMatrix
    matrix =. matrix#~matrix~:0
    costs =. ModelCosts#~ModelCosts~:0
    rhs =. ModelRhs#~ModelRhs~:0
    bounds =. 0$0x
    for_bound. ModelLower,ModelUpper do.
        value =. >bound
        if. finite value do.
            if. value~:0 do. bounds =. bounds,value end.
        end.
    end.
    text =. 'STATS nonzeros ',integer #matrix
    sets =. (<matrix),(<costs),(<rhs),<bounds
    names =. ;:'matrix objective rhs bounds'
    for_i. i.4 do.
        values =. |i{::sets
        text =. text,' ',(i{::names),' '
        if. #values do.
            text =. text,(fraction <./values),' ',fraction >./values
        else.
            text =. text,'- -'
        end.
    end.
    text
)
range_endpoints =: 3 : 0
    'origin coefficients numerators' =. y
    lower =. upper =. ''
    positive =. I.coefficients>0
    negative =. I.coefficients<0
    if. #positive do. lower =. origin+>./(positive{numerators)%positive{coefficients end.
    if. #negative do. upper =. origin+<./(negative{numerators)%negative{coefficients end.
    (<lower),<upper
)
objective_range =: 3 : 0
    'variable reduced nonbasic' =. y
    'kind offset columns signs upper_row' =. variable{::Mappings
    h =. (#ColumnNames)$0x
    h =. (DirectionSign*signs)columns}h
    eta =. nonbasic{reduced_costs h
    numerators =. -nonbasic{reduced
    range_endpoints(<variable{ModelCosts),(<eta),<numerators
)
rhs_range =: 3 : 0
    rho =. (y{RowSigns)*(y{InitialBasis){"1 TMatrix
    if. +./(rho~:0)*.TBasis{Artificial do.
        (<y{ModelRhs),<y{ModelRhs
    else.
        range_endpoints(<y{ModelRhs),(<rho),<-TBeta
    end.
)
variable_status =: 3 : 0
    'kind offset columns signs upper_row' =. y{::Mappings
    if. kind-:'split' do.
        if. +./columns e.TBasis do. 'basic' else. 'zero' end.
    elseif. kind-:'reflect' do.
        if. ({.columns)e.TBasis do. 'basic' else. 'upper' end.
    elseif. -.({.columns)e.TBasis do.
        'lower'
    else.
        if. upper_row~:_1 do.
            if. -.(upper_row{SlackColumns)e.TBasis do. 'upper' return. end.
        end.
        'basic'
    end.
)
sensitivity_lines =: 3 : 0
    result =. y
    restore_lp result
    objective =. 1{::result
    solution =. 2{::result
    reduced =. reduced_costs Phase2Costs
    nonbasic =. I.(-.Artificial)*.-.(i.#ColumnNames)e.TBasis
    dual =. -DirectionSign*(#ModelRhs){.RowSigns*InitialBasis{reduced
    variable_reduced =. ModelCosts
    for_j. i.#ModelVariables do.
        value =. (j{ModelCosts)-dual dot j{"1 ModelMatrix
        variable_reduced =. value j}variable_reduced
    end.
    primal_degeneracy =. +/(-.TBasis{Artificial)*.TBeta=0
    dual_degeneracy =. +/0=nonbasic{reduced
    dual_objective =. (dual dot ModelRhs)+variable_reduced dot solution
    kind =. 'lp'
    if. +./ModelInteger do. kind =. 'relaxation' end.
    lines =. <emit 'MODEL';ModelName;kind;'objective';objective
    lines =. lines,<'BASIS ',' 'join TBasis{ColumnNames
    lines =. lines,<emit 'DEGENERACY primal';primal_degeneracy;'dual';dual_degeneracy
    lines =. lines,<emit 'DUAL objective';dual_objective
    for_i. i.#ModelRhs do.
        'lower upper' =. rhs_range i
        text =. emit 'CONSTRAINT';(i{::ConstraintNames);'price';(i{dual);'rhs';(i{ModelRhs)
        lines =. lines,<text,' range ',(1 endpoint lower),' ',0 endpoint upper
    end.
    for_j. i.#ModelVariables do.
        'lower upper' =. objective_range(<j),(<reduced),<nonbasic
        text =. emit 'VARIABLE';(j{::ModelVariables);(variable_status j);'value';(j{solution)
        text =. text,' reduced ',(fraction j{variable_reduced),' cost ',fraction j{ModelCosts
        lines =. lines,<text,' range ',(1 endpoint lower),' ',0 endpoint upper
    end.
    lines
)
solve_model =: 3 : 0
    'level limit' =. y
    LogLevel =: level
    if. +./ModelInteger do. branch_search limit return. end.
    result =. solve_lp(<ModelLower),(<ModelUpper),(<1),<level
    status =. 0{::result
    solution =. i.0
    if. status-:'OPTIMAL' do. solution =. 2{::result end.
    (<status),(<1{::result),(<solution),(<, <result),(<result),(<0$a:),<1
)
solution_lines =: 3 : 0
    'status objective solution solves root tree_lines nodes' =. y
    restore_lp root
    integer_count =. +/ModelInteger
    text =. emit 'MODEL';ModelName;ModelDirection;'variables';(#ModelVariables);'constraints';(#ModelRhs);'integers';integer_count
    lines =. (<text),(<statistics_line ''),<'STATUS ',status
    if. #solution do. lines =. lines,<emit 'OBJECTIVE';objective;'approx';approximate objective end.
    if. integer_count*. 'OPTIMAL'-:0{::root do.
        relaxation =. 1{::root
        lines =. lines,<emit 'RELAXATION';relaxation;'approx';approximate relaxation
    end.
    if. 'INFEASIBLE'-:0{::root do.
        lines =. lines,<emit 'INFEASIBILITY';6{::root
        multipliers =. farkas ''
        for_i. i.#RowNames do.
            lines =. lines,<emit 'FARKAS';(i{::RowNames);i{multipliers
        end.
    end.
    values =. solution
    if. status-:'UNBOUNDED' do. values =. 2{::root end.
    for_j. i.#values do.
        lines =. lines,<emit 'VALUE';(j{::ModelVariables);j{values
    end.
    if. status-:'UNBOUNDED' do.
        'ray rate' =. unbounded_ray root
        for_j. i.#ray do. lines =. lines,<emit 'RAY';(j{::ModelVariables);j{ray end.
        lines =. lines,<emit 'RATE';rate
    end.
    if. #solution do.
        for_i. i.#ModelRhs do.
            value =. (i{ModelMatrix)dot solution
            margin =. value-i{ModelRhs
            if. '<='-:i{::ModelComparisons do. margin =. (i{ModelRhs)-value end.
            lines =. lines,<emit 'ROW';(i{::ConstraintNames);value;margin
        end.
    end.
    if. integer_count do. lines =. lines,<emit 'NODES';nodes end.
    pivots =. 0
    for_lp. solves do. pivots =. pivots+11{::>lp end.
    lines,<emit 'PIVOTS';pivots
)
write_lines =: 4 : 0
    text =. ''
    for_line. y do. text =. text,(>line),LF end.
    text 1!:2 <'output/',x
)
run =: 3 : 0
    read_settings ''
    models =. read_models ''
    iterations =. solutions =. sensitivity =. tree =. 0$a:
    summary =. <'model,status,objective,approx,relaxation,nodes,pivots'
    status_names =. ;:'OPTIMAL INFEASIBLE UNBOUNDED NODE_LIMIT ERROR'
    statuses =. 5$0
    total_solves =. total_p1 =. total_p2 =. total_drives =. analyzed =. 0
    integer_models =. integer_nodes =. limited_models =. 0
    for_parsed. models do.
        parsed =. >parsed
        name =. 0{::parsed
        'model error' =. content_check parsed
        if. #error do.
            statuses =. (1+4{statuses)4}statuses
            iterations =. iterations,<'MODEL ',name,' error'
            'line message' =. error
            solutions =. solutions,(<'MODEL ',name),<'STATUS ERROR line ',(integer line),' ',message
            sensitivity =. sensitivity,<'MODEL ',name,' skipped ERROR'
            summary =. summary,<name,',ERROR,-,-,-,0,0'
            continue.
        end.
        set_model model
        level =. DefaultLevel
        index =. LogNames i.<name
        if. index<#LogNames do. level =. index{LogValues end.
        limit =. DefaultLimit
        index =. LimitNames i.<name
        if. index<#LimitNames do. limit =. index{LimitValues end.
        result =. solve_model level,limit
        'status objective solution solves root tree_lines nodes' =. result
        index =. status_names i.<status
        statuses =. (1+index{statuses)index}statuses
        iterations =. iterations,<emit 'MODEL';name;'level';level
        pivots =. 0
        for_lp. solves do.
            lp =. >lp
            iterations =. iterations,12{::lp
            total_solves =. total_solves+1
            total_p1 =. total_p1+7{::lp
            total_p2 =. total_p2+8{::lp
            total_drives =. total_drives+9{::lp
            pivots =. pivots+11{::lp
        end.
        solutions =. solutions,solution_lines result
        if. 'OPTIMAL'-:0{::root do.
            analyzed =. analyzed+1
            sensitivity =. sensitivity,sensitivity_lines root
        else.
            sensitivity =. sensitivity,<'MODEL ',name,' skipped ',0{::root
        end.
        if. +./ModelInteger do.
            integer_models =. integer_models+1
            integer_nodes =. integer_nodes+nodes
            limited_models =. limited_models+status-:'NODE_LIMIT'
            text =. emit 'MODEL';name;ModelDirection;'integers';(+/ModelInteger);'node_limit';limit
            tree =. tree,(<text),tree_lines
        end.
        objective_text =. approximate_text =. ,'-'
        if. finite objective do.
            objective_text =. fraction objective
            approximate_text =. approximate objective
        end.
        fields =. name;status;objective_text;approximate_text;(fraction 1{::root);(integer #solves);integer pivots
        summary =. summary,<','join fields
    end.
    total_pivots =. total_p1+total_p2+total_drives
    text =. emit 'TOTAL solves';total_solves;'phase1';total_p1;'phase2';total_p2
    iterations =. iterations,<text,' drives ',(integer total_drives),' pivots ',integer total_pivots
    text =. emit 'SUMMARY models';(#models);'optimal';(0{statuses);'infeasible';(1{statuses);'unbounded';2{statuses
    solutions =. solutions,<text,' node_limit ',(integer 3{statuses),' error ',integer 4{statuses
    sensitivity =. sensitivity,<emit 'SUMMARY analyzed';analyzed;'skipped';(#models)-analyzed
    tree =. tree,<emit 'SUMMARY models';integer_models;'nodes';integer_nodes;'node_limit';limited_models
    try.
        1!:5 <'output'
    catch.
    end.
    'iterations.txt'write_lines iterations
    'solutions.txt'write_lines solutions
    'sensitivity.txt'write_lines sensitivity
    'bnb_tree.txt'write_lines tree
    'summary.csv'write_lines summary
)
run ''
