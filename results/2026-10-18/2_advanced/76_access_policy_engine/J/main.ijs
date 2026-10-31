load 'expressions.ijs'
load 'rbac.ijs'
load 'policy_parser.ijs'
load 'combining.ijs'
load 'analysis.ijs'
Letters =: 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
DecisionNames =: 'PERMIT';'DENY';'NOT_APPLICABLE';'INDETERMINATE{D}';'INDETERMINATE{P}';'INDETERMINATE{DP}'
TargetNames =: 'MATCH';'NO_MATCH';'INDETERMINATE'
integer =: 3 : 0
    text =. ":y
    '-'(I.text='_')}text
)
parse_int =: 3 : '". ''_''(I.y=''-'')}y'
intdiv =: 4 : '<.(x:x)%x:y'
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do.
            result =. result,x
        end.
        result =. result,i{::y
    end.
    result
)
read_lines =: 3 : '<;._2 (1!:1 <y)'
split_words =: 3 : '<;._1 '' '',y'
split_commas =: 3 : '<;._1 '','',y'
split_first =: 3 : 0
    at =. y i.' '
    (at{.y);(>:at)}.y
)
trim =: 3 : 0
    text =. y
    while. #text do.
        if. ' '~:{.text do.
            break.
        end.
        text =. }.text
    end.
    while. #text do.
        if. ' '~:{:text do.
            break.
        end.
        text =. }:text
    end.
    text
)
split_text =: 4 : 0
    result =. 0$a:
    start =. 0
    for_at. I.x E.y do.
        if. at>:start do.
            result =. result,<(at-start){.start}.y
            start =. at+#x
        end.
    end.
    result,<start}.y
)
join_blocks =: 3 : 0
    result =. 0$a:
    for_block. y do.
        if. #result do.
            result =. result,<''
        end.
        result =. result,>block
    end.
    result
)
value =: 4 : '(<x),<y'
empty_map =: 3 : '(<0$a:),<0$a:'
map_has =: 4 : '(<x)e.0{::y'
map_get =: 4 : 0
    'keys values' =. y
    index =. keys i.<x
    if. index=#keys do.
        4 value 'missing ',x
    else.
        index{::values
    end.
)
map_put =: 4 : 0
    'key datum' =. x
    'keys values' =. y
    index =. keys i.<key
    if. index=#keys do.
        keys =. keys,<key
        values =. values,<datum
    else.
        values =. (<datum)index}values
    end.
    (<keys),<values
)
input_value =: 3 : 0
    if. (<y)e.'true';'false' do.
        2 value y-:'true'
    elseif. '['={.y do.
        elements =. 0$a:
        if. -.y-:'[]' do.
            elements =. split_commas }:}.y
        end.
        3 value elements
    elseif. ({.y)e.'-0123456789' do.
        0 value parse_int y
    else.
        1 value y
    end.
)
value_notation =: 3 : 0
    'kind data' =. y
    select. kind
    case. 0 do. integer data
    case. 1 do. '"',data,'"'
    case. 2 do.
        if. data do. 'true' else. 'false' end.
    case. 3 do.
        values =. 0$a:
        for_item. data do.
            values =. values,<'"',(>item),'"'
        end.
        '[',(','join values),']'
    end.
)
attributes_from =: 3 : 0
    result =. empty_map ''
    for_field. y do.
        text =. >field
        equals =. text i.'='
        name =. equals{.text
        datum =. input_value (equals+1)}.text
        result =. ((<name),<datum)map_put result
    end.
    result
)
first_error =: 3 : 0
    for_datum. y do.
        datum =. >datum
        if. 4=0{::datum do.
            datum return.
        end.
    end.
    0$a:
)
boolean_result =: 4 : 0
    'name veto' =. x
    first =. 0$a:
    found =. 0
    for_datum. y do.
        datum =. >datum
        kind =. 0{::datum
        if. -.kind e.2 4 do.
            datum =. 4 value 'type ',name
            kind =. 4
        end.
        if. kind=2 do.
            if. veto=1{::datum do.
                found =. 1
            end.
        elseif. 0=#first do.
            first =. datum
        end.
    end.
    if. found do.
        2 value veto
    elseif. #first do.
        first
    else.
        2 value -.veto
    end.
)
operation =: 4 : 0
    name =. x
    if. 1=#name do.
        name =. {.name
    end.
    values =. y
    error =. first_error values
    if. #error do.
        error return.
    end.
    kinds =. i.0
    for_datum. values do.
        kinds =. kinds,0{::>datum
    end.
    first =. 1{::0{::values
    if. (<name)e.'+';'-';'*';'<';'<=';'>';'>=' do.
        if. *./kinds=0 do.
            if. 1=#values do.
                0 value -first return.
            end.
            second =. 1{::1{::values
            select. name
            case. '+' do. 0 value first+second return.
            case. '-' do. 0 value first-second return.
            case. '*' do. 0 value first*second return.
            case. '<' do. 2 value first<second return.
            case. '<=' do. 2 value first<:second return.
            case. '>' do. 2 value first>second return.
            case. '>=' do. 2 value first>:second return.
            end.
        end.
    elseif. (<name)e.'==';'!=' do.
        if. (0{kinds)=1{kinds do.
            if. (0{kinds)e.0 1 2 do.
                second =. 1{::1{::values
                if. (0{kinds)=1 do.
                    same =. first-:second
                else.
                    same =. first=second
                end.
                if. name-:'!=' do.
                    same =. -.same
                end.
                2 value same return.
            end.
        end.
    elseif. name-:'in' do.
        if. kinds-:1 3 do.
            2 value (<first)e.1{::1{::values return.
        end.
    elseif. name-:'not' do.
        if. kinds-:,2 do.
            2 value -.first return.
        end.
    elseif. (<name)e.'starts_with';'^=' do.
        if. kinds-:1 1 do.
            second =. 1{::1{::values
            2 value second-:(#second){.first return.
        end.
    elseif. name-:'size' do.
        if. kinds-:,3 do.
            0 value #first return.
        end.
    end.
    4 value 'type ',name
)
evaluate_expression =: 4 : 0
    context =. x
    'attributes current' =. context
    'name payload arguments' =. y
    select. name
    case. 'literal' do. payload return.
    case. 'attribute' do. payload map_get attributes return.
    case. 'it' do. current return.
    case. 'present' do.
        reference =. 1{::0{::arguments
        2 value reference map_has attributes return.
    end.
    if. (<name)e.'any_of';'all_of' do.
        bag =. context evaluate_expression 0{::arguments
        if. 4=0{::bag do.
            bag return.
        end.
        if. 3~:0{::bag do.
            4 value 'type ',name return.
        end.
        results =. 0$a:
        for_item. 1{::bag do.
            nested =. (<attributes),<1 value >item
            results =. results,<nested evaluate_expression 1{::arguments
        end.
        (name;(name-:'any_of'))boolean_result results return.
    end.
    values =. 0$a:
    for_argument. arguments do.
        values =. values,<context evaluate_expression >argument
    end.
    if. (<name)e.'and';'or' do.
        (name;(name-:'or'))boolean_result values
    else.
        name operation values
    end.
)
target_group =: 4 : 0
    statuses =. i.0
    first_reason =. ''
    for_result. y do.
        'status reason' =. >result
        statuses =. statuses,status
        if. (status=2)*.0=#first_reason do.
            first_reason =. reason
        end.
    end.
    if. x do.
        if. 1 e.statuses do.
            1;'' return.
        end.
        if. *./statuses=0 do.
            0;'' return.
        end.
    elseif. 0 e.statuses do.
        0;'' return.
    end.
    if. 2 e.statuses do.
        2;first_reason
    else.
        1;''
    end.
)
match_clause =: 4 : 0
    attributes =. x
    'reference mandatory operator literal' =. y
    if. -.reference map_has attributes do.
        if. mandatory do.
            2;'missing ',reference
        else.
            1;''
        end.
        return.
    end.
    source =. reference map_get attributes
    items =. 0$a:
    if. 3=0{::source do.
        for_item. 1{::source do.
            items =. items,<1 value >item
        end.
    else.
        items =. <source
    end.
    context =. (<attributes),<1 value ''
    comparison =. context evaluate_expression literal
    results =. 0$a:
    for_item. items do.
        results =. results,<operator operation item,<comparison
    end.
    matched =. 0
    for_result. results do.
        result =. >result
        if. 2=0{::result do.
            matched =. matched+.1{::result
        end.
    end.
    if. matched do.
        0;'' return.
    end.
    error =. first_error results
    if. #error do.
        2;1{::error
    else.
        1;''
    end.
)
evaluate_target =: 4 : 0
    lines =. 0$a:
    for_line. y{::Targets do.
        alternatives =. 0$a:
        for_alternative. >line do.
            clauses =. 0$a:
            for_clause. >alternative do.
                clauses =. clauses,<x match_clause >clause
            end.
            alternatives =. alternatives,<1 target_group clauses
        end.
        lines =. lines,<0 target_group alternatives
    end.
    1 target_group lines
)
new_evaluation =: 4 : 0
    (<y),(<x),(<2),(<'') ,(<_1),(<0$a:),(<0$a:),(<0$a:),<0$a:
)
attach_items =: 4 : 0
    attributes =. x
    result =. y
    element =. 0{::result
    effect =. 2{::result
    obligations =. 0$a:
    advice =. 0$a:
    for_state. 6{::result do.
        'mode payload' =. >state
        if. mode=2 do.
            if. effect=2{::payload do.
                obligations =. obligations,7{::payload
                advice =. advice,8{::payload
            end.
        end.
    end.
    context =. (<attributes),<1 value ''
    for_kind. i.2 do.
        definitions =. element{::Obligations
        if. kind=1 do.
            definitions =. element{::Advice
        end.
        for_definition. definitions do.
            'required identifier arguments' =. >definition
            if. required~:effect do.
                continue.
            end.
            values =. 0$a:
            names =. 0$a:
            for_argument. arguments do.
                'name tree' =. >argument
                names =. names,<name
                values =. values,<context evaluate_expression tree
            end.
            error =. first_error values
            if. #error do.
                if. kind=0 do.
                    result =. (<4-effect)2}result
                    result =. (<'obligation ',identifier,': ',1{::error)3}result
                    result =. (<_1)4}result
                    result =. (<0$a:)7}result
                    result =. (<0$a:)8}result
                    result return.
                end.
                continue.
            end.
            text =. identifier
            for_i. i.#names do.
                text =. text,' ',(i{::names),'=',value_notation i{::values
            end.
            item =. identifier;text
            if. kind=0 do.
                obligations =. obligations,<item
            else.
                advice =. advice,<item
            end.
        end.
    end.
    result =. (<obligations)7}result
    (<advice)8}result
)
evaluate_rule =: 4 : 0
    'attributes coverage attachments' =. x
    element =. y
    target =. attributes evaluate_target element
    result =. target new_evaluation element
    'status reason' =. target
    effect =. (element{::Behaviors)-:'DENY'
    if. status=2 do.
        result =. (<4-effect)2}result
        result =. (<reason)3}result
    elseif. status=0 do.
        condition =. 2 value 1
        tree =. element{::Conditions
        if. #tree do.
            condition =. ((<attributes),<1 value '')evaluate_expression tree
        end.
        if. -. (0{::condition)e.2 4 do.
            condition =. 4 value 'type condition'
        end.
        result =. (<condition)5}result
        if. 4=0{::condition do.
            result =. (<4-effect)2}result
            result =. (<1{::condition)3}result
        elseif. 1{::condition do.
            result =. (<effect)2}result
            result =. (<element)4}result
            if. attachments do.
                result =. attributes attach_items result
            end.
        end.
    end.
    if. coverage do.
        decision =. 2{::result
        symbol =. 'I'
        if. decision<3 do.
            symbol =. decision{'PD-'
        end.
        CurrentCoverage =: symbol element}CurrentCoverage
    end.
    result
)
evaluate_element =: 4 : 0
    context =. x
    'attributes coverage' =. context
    element =. y
    if. 'rule'-:element{::ElementKinds do.
        ((<attributes),(<coverage),<1)evaluate_rule element return.
    end.
    target =. attributes evaluate_target element
    result =. target new_evaluation element
    'status target_reason' =. target
    if. status=1 do.
        result return.
    end.
    'decision reason children' =. context combine_children element
    if. status=2 do.
        if. decision<2 do.
            decision =. 4-decision
        end.
        if. decision>:3 do.
            reason =. target_reason
        end.
    end.
    result =. (<decision)2}result
    result =. (<reason)3}result
    result =. (<children)6}result
    if. decision<2 do.
        decisive =. element
        for_state. children do.
            'mode payload' =. >state
            if. mode=2 do.
                if. decision=2{::payload do.
                    decisive =. 4{::payload
                    break.
                end.
            end.
        end.
        result =. (<decisive)4}result
        result =. attributes attach_items result
    end.
    result
)
decision_notation =: 4 : 0
    text =. x{::DecisionNames
    if. x>:3 do.
        text =. text,' (',y,')'
    end.
    text
)
final_notation =: 3 : 0
    decision =. 2{::y
    text =. decision decision_notation 3{::y
    if. decision<2 do.
        text =. text,' by ',(4{::y){::ElementIds
    end.
    text
)
tree_lines =: 4 : 0
    depth =. x
    result =. y
    element =. 0{::result
    'status reason' =. 1{::result
    prefix =. (2+2*depth)$' '
    line =. prefix,(element{::ElementKinds),' ',(element{::ElementIds),' ',(element{::Behaviors),' target ',status{::TargetNames
    if. ('rule'-:element{::ElementKinds)*.status=0 do.
        condition =. 5{::result
        label =. 'INDETERMINATE'
        if. 2=0{::condition do.
            label =. (1{::condition){::'FALSE';'TRUE'
        end.
        line =. line,' condition ',label
    end.
    lines =. <line,' -> ',(2{::result)decision_notation 3{::result
    if. (-.'rule'-:element{::ElementKinds)*.status~:1 do.
        children =. element{::Children
        states =. 6{::result
        for_i. i.#children do.
            child =. i{children
            'mode payload' =. i{::states
            if. mode=2 do.
                lines =. lines,(depth+1)tree_lines payload
            elseif. mode=0 do.
                lines =. lines,<prefix,'  ',(child{::ElementKinds),' ',(child{::ElementIds),' skipped'
            else.
                'checked checked_reason' =. payload
                text =. prefix,'  ',(child{::ElementKinds),' ',(child{::ElementIds),' ',(child{::Behaviors),' target ',checked{::TargetNames
                if. checked=2 do.
                    text =. text,' (',checked_reason,')'
                end.
                lines =. lines,<text
            end.
        end.
    end.
    lines
)
read_attributes =: 3 : 0
    SubjectNames =: 0$a:
    SubjectAttributes =: 0$a:
    ResourceNames =: 0$a:
    ResourceTypes =: 0$a:
    ResourceAttributes =: 0$a:
    DomainNames =: 0$a:
    DomainValues =: 0$a:
    Reference =: empty_map ''
    for_line. read_lines 'input/attributes.txt' do.
        fields =. split_words >line
        kind =. 0{::fields
        fields =. }.fields
        select. kind
        case. 'SUBJECT' do.
            SubjectNames =: SubjectNames,0{fields
            SubjectAttributes =: SubjectAttributes,<attributes_from }.fields
        case. 'RESOURCE' do.
            ResourceNames =: ResourceNames,0{fields
            ResourceTypes =: ResourceTypes,1{fields
            ResourceAttributes =: ResourceAttributes,<attributes_from 2}.fields
        case. 'DOMAIN' do.
            DomainNames =: DomainNames,0{fields
            values =. 0$a:
            for_field. }.fields do.
                values =. values,<input_value >field
            end.
            DomainValues =: DomainValues,<values
        case. 'REFERENCE' do.
            Reference =: attributes_from fields
        end.
    end.
    i.0
)
read_requests =: 3 : 0
    Requests =: 0$a:
    for_line. read_lines 'input/requests.txt' do.
        fields =. split_words >line
        explain =. 'EXPLAIN'-:_1{::fields
        if. explain do.
            fields =. }:fields
        end.
        environment =. attributes_from 5}.fields
        Requests =: Requests,<(5{.fields),(<environment),<explain
    end.
    i.0
)
check_request =: 3 : 0
    'identifier user specification action resource environment explain' =. y
    if. -. (<user)e.SubjectNames do.
        'unknown user ',user return.
    end.
    if. -. (<resource)e.ResourceNames do.
        'unknown resource ',resource return.
    end.
    day =. 'day'map_get environment
    if. 0~:0{::day do.
        'bad day' return.
    end.
    number =. 1{::day
    if. (number<1)+.number>365 do.
        'bad day' return.
    end.
    ''
)
activate_roles =: 3 : 0
    'user specification day' =. y
    authorized =. user authorized_roles day
    candidates =. 0$a:
    if. (,specification)-:,'*' do.
        candidates =. (roles_by_name authorized){RoleNames
    elseif. -.(,specification)-:,'-' do.
        candidates =. split_commas specification
    end.
    active =. i.0
    seen =. 0$a:
    activations =. 0$a:
    for_candidate. candidates do.
        name =. >candidate
        role =. RoleNames i.<name
        reason =. ''
        if. role=#RoleNames do.
            reason =. 'unknown'
        elseif. (<name)e.seen do.
            reason =. 'duplicate'
        elseif. -.role e.authorized do.
            reason =. 'unauthorized'
        else.
            closure =. role_closure active,role
            for_constraint. DSDConstraints do.
                'constraint_name cardinality roles' =. >constraint
                if. cardinality<:+/roles e.closure do.
                    reason =. 'dsd ',constraint_name
                    break.
                end.
            end.
        end.
        seen =. seen,<name
        if. 0=#reason do.
            active =. active,role
        end.
        activations =. activations,<name;reason
    end.
    roles =. roles_by_name role_closure active
    (<activations),<roles
)
qualified_attributes =: 4 : 0
    'keys values' =. y
    names =. 0$a:
    for_name. keys do.
        names =. names,<x,'.',>name
    end.
    (<names),<values
)
merge_maps =: 4 : 0
    result =. y
    'keys values' =. x
    for_i. i.#keys do.
        result =. ((i{keys),i{values)map_put result
    end.
    result
)
prepare_request =: 3 : 0
    'identifier user specification action resource environment explain' =. y
    day =. 1{::'day'map_get environment
    'activations roles' =. activate_roles user;specification;day
    resource_index =. ResourceNames i.<resource
    resource_type =. resource_index{::ResourceTypes
    permission =. action,' ',resource_type
    grant =. _1
    for_role. roles do.
        if. (<permission)e.role{::RolePermissions do.
            grant =. role
            break.
        end.
    end.
    subject_index =. SubjectNames i.<user
    attributes =. 'subject'qualified_attributes subject_index{::SubjectAttributes
    attributes =. ((<'subject.id'),<1 value user)map_put attributes
    attributes =. ((<'subject.role'),<3 value roles{RoleNames)map_put attributes
    attributes =. ((<'subject.rbac'),<2 value grant>:0)map_put attributes
    attributes =. ('resource'qualified_attributes resource_index{::ResourceAttributes)merge_maps attributes
    attributes =. ((<'resource.id'),<1 value resource)map_put attributes
    attributes =. ((<'resource.type'),<1 value resource_type)map_put attributes
    attributes =. ((<'action.id'),<1 value action)map_put attributes
    attributes =. ('environment'qualified_attributes environment)merge_maps attributes
    (<activations),(<roles),(<grant),(<attributes),<resource_type
)
trace_request =: 3 : 0
    'request prepared result' =. y
    'identifier user specification action resource environment explain' =. request
    'activations roles grant attributes resource_type' =. prepared
    lines =. <'request ',identifier
    day =. 1{::'day'map_get environment
    lines =. lines,<'  user ',user,' resource ',resource,' type ',resource_type,' action ',action,' day ',integer day
    for_activation. activations do.
        'role reason' =. >activation
        text =. '  activate ',role,' ok'
        if. #reason do.
            text =. '  activate ',role,' refused ',reason
        end.
        lines =. lines,<text
    end.
    text =. '-'
    if. #roles do.
        text =. ','join roles{RoleNames
    end.
    lines =. lines,<'  roles ',text
    text =. 'no'
    if. grant>:0 do.
        text =. 'yes ',grant{::RoleNames
    end.
    lines =. lines,<'  rbac ',text
    lines =. lines,0 tree_lines result
    lines,<'  decision ',final_notation result
)
count_attachment =: 4 : 0
    names =. ObligationNames
    counts =. ObligationCounts
    if. x=1 do.
        names =. AdviceNames
        counts =. AdviceCounts
    end.
    index =. names i.<y
    if. index=#names do.
        names =. names,<y
        counts =. counts,1
    else.
        counts =. (1+index{counts)index}counts
    end.
    if. x=0 do.
        ObligationNames =: names
        ObligationCounts =: counts
    else.
        AdviceNames =: names
        AdviceCounts =: counts
    end.
    i.0
)
process_requests =: 3 : 0
    Coverage =: (#ElementIds)$<''
    GrantCounts =: (#Grants)$0
    DecisionCounts =: 5$0
    DecisiveCounts =: (#ElementIds)$0
    RefusedCount =: 0
    ObligationNames =: 0$a:
    ObligationCounts =: i.0
    AdviceNames =: 0$a:
    AdviceCounts =: i.0
    DecisionLines =: 0$a:
    explanations =. 0$a:
    for_request_box. Requests do.
        request =. >request_box
        'identifier user specification action resource environment explain' =. request
        CurrentCoverage =: (#ElementIds)$'.'
        error =. check_request request
        if. #error do.
            DecisionLines =: DecisionLines,<identifier,' ERROR ',error
            DecisionCounts =: (1+4{DecisionCounts)4}DecisionCounts
            if. explain do.
                explanations =. explanations,< (<'request ',identifier),<'  error ',error
            end.
        else.
            prepared =. prepare_request request
            'activations roles grant attributes resource_type' =. prepared
            result =. ((<attributes),<1)evaluate_element 0
            DecisionLines =: DecisionLines,<identifier,' ',final_notation result
            for_activation. activations do.
                'role reason' =. >activation
                if. #reason do.
                    DecisionLines =: DecisionLines,<'  refused ',role,' ',reason
                    RefusedCount =: RefusedCount+1
                end.
            end.
            for_kind. i.2 do.
                for_item. (7+kind){::result do.
                    'item_id text' =. >item
                    label =. kind{::'obligation';'advice'
                    DecisionLines =: DecisionLines,<'  ',label,' ',text
                    kind count_attachment item_id
                end.
            end.
            if. grant>:0 do.
                for_i. i.#Grants do.
                    'role grant_action grant_type' =. i{::Grants
                    if. (role=grant)*.(grant_action-:action)*.grant_type-:resource_type do.
                        GrantCounts =: (1+i{GrantCounts)i}GrantCounts
                        break.
                    end.
                end.
            end.
            decision =. 2{::result
            category =. 3<.decision
            DecisionCounts =: (1+category{DecisionCounts)category}DecisionCounts
            if. decision<2 do.
                decisive =. 4{::result
                DecisiveCounts =: (1+decisive{DecisiveCounts)decisive}DecisiveCounts
            end.
            if. explain do.
                explanations =. explanations,<trace_request (<request),(<prepared),<result
            end.
        end.
        for_rule. RuleIndices do.
            Coverage =: (<(rule{::Coverage),rule{CurrentCoverage)rule}Coverage
        end.
    end.
    TraceLines =: join_blocks explanations
    i.0
)
permission_report =: 3 : 0
    users =. 0$a:
    for_assignment. Assignments do.
        users =. users,0{>assignment
    end.
    users =. /:~ ~.users
    blocks =. 0$a:
    for_user. users do.
        user =. >user
        assigned =. ((#RoleNames),366)$0
        authorized =. assigned
        for_assignment. Assignments do.
            'owner role first last' =. >assignment
            if. user-:owner do.
                days =. role{assigned
                days =. 1 (first+i.1+last-first)}days
                assigned =. days role}assigned
            end.
        end.
        assigned_roles_list =. I.+/"1 assigned
        for_role. assigned_roles_list do.
            for_inherited. role_closure ,role do.
                authorized =. ((inherited{authorized)+.role{assigned)inherited}authorized
            end.
        end.
        authorized_roles_list =. I.+/"1 authorized
        lines =. <'user ',user
        for_role. roles_by_name assigned_roles_list do.
            lines =. lines,<'  assigned ',(role{::RoleNames),' ',day_notation I.role{assigned
        end.
        for_role. roles_by_name authorized_roles_list do.
            lines =. lines,<'  authorized ',(role{::RoleNames),' ',day_notation I.role{authorized
        end.
        pairs =. 0$a:
        for_role. authorized_roles_list do.
            pairs =. pairs,role{::RolePermissions
        end.
        pairs =. /:~ ~.pairs
        for_pair. pairs do.
            pair =. >pair
            'action kind' =. split_words pair
            via =. i.0
            days =. 366$0
            for_role. roles_by_name authorized_roles_list do.
                if. (<pair)e.role{::RolePermissions do.
                    via =. via,role
                    days =. days+.role{authorized
                end.
            end.
            effective =. '-'
            if. (<user)e.SubjectNames do.
                resources =. I.ResourceTypes=<kind
                permitted =. 0
                for_resource. resources do.
                    request =. (<'') ,(<user),(<'*'),(<action),(resource{ResourceNames),(<Reference),<0
                    prepared =. prepare_request request
                    attributes =. 3{::prepared
                    result =. ((<attributes),<0)evaluate_element 0
                    permitted =. permitted+0=2{::result
                end.
                effective =. (integer permitted),'/',integer #resources
            end.
            text =. '  permission ',pair,' ',(day_notation I.days),' via ',(','join via{RoleNames),' effective ',effective
            lines =. lines,<text
        end.
        blocks =. blocks,<lines
    end.
    join_blocks blocks
)
point_example =: 3 : 0
    'names values' =. y
    parts =. 0$a:
    for_i. i.#DomainNames do.
        if. 1<#i{::DomainValues do.
            parts =. parts,<(i{::names),'=',value_notation i{::values
        end.
    end.
    ' 'join parts
)
domain_analysis =: 3 : 0
    count =. #ElementIds
    counts =. count$0
    examples =. count$<'-'
    ancestors =. count$<i.0
    shadowed =. count$0
    blockers =. count$<i.0
    for_rule. RuleIndices do.
        chain =. i.0
        parent =. rule{Parents
        while. parent>:0 do.
            chain =. chain,parent
            parent =. parent{Parents
        end.
        ancestors =. (<chain)rule}ancestors
        parent =. rule{Parents
        if. 'first-applicable'-:parent{::Behaviors do.
            shadowed =. 1 rule}shadowed
        end.
    end.
    pairs =. 0$a:
    for_policy. PolicyIndices do.
        children =. policy{::Children
        for_i. i.#children do.
            earlier =. i{children
            remaining =. (#children)-(i+1)
            for_j. (i+1)+i.remaining do.
                later =. j{children
                if. -. (earlier{::Behaviors)-:later{::Behaviors do.
                    pairs =. pairs,<policy,earlier,later
                end.
            end.
        end.
    end.
    conflict_counts =. (#pairs)$0
    point_count =. domain_size ''
    for_point. i.point_count do.
        attributes =. point_attributes point
        statuses =. count$1
        for_element. I.ElementKinds~:<'rule' do.
            target =. attributes evaluate_target element
            statuses =. (0{::target)element}statuses
        end.
        standalone =. count$2
        for_rule. RuleIndices do.
            result =. ((<attributes),(<0),<0)evaluate_rule rule
            standalone =. (2{::result)rule}standalone
        end.
        applying =. count$0
        for_rule. RuleIndices do.
            if. rule{standalone<2 do.
                if. *./0=(rule{::ancestors){statuses do.
                    applying =. 1 rule}applying
                    if. 0=rule{counts do.
                        examples =. (<point_example attributes)rule}examples
                    end.
                    counts =. (1+rule{counts)rule}counts
                    if. rule{shadowed do.
                        earlier =. rule find_blocker standalone
                        if. earlier=_1 do.
                            shadowed =. 0 rule}shadowed
                        else.
                            blockers =. (<~.(rule{::blockers),earlier)rule}blockers
                        end.
                    end.
                end.
            end.
        end.
        for_i. i.#pairs do.
            'policy earlier later' =. i{::pairs
            if. (earlier{applying)*.later{applying do.
                conflict_counts =. (1+i{conflict_counts)i}conflict_counts
            end.
        end.
    end.
    lines =. <'applicability ',integer point_count
    for_rule. RuleIndices do.
        lines =. lines,<'  ',(rule{::ElementIds),' ',(integer rule{counts),' ',rule{::examples
    end.
    dead =. RuleIndices#~0=RuleIndices{counts
    lines =. lines,<'dead ',integer #dead
    for_rule. dead do.
        lines =. lines,<'  ',rule{::ElementIds
    end.
    hidden =. RuleIndices#~(RuleIndices{shadowed)*.0<RuleIndices{counts
    lines =. lines,<'shadowed ',integer #hidden
    for_rule. hidden do.
        names =. (/:~rule{::blockers){ElementIds
        lines =. lines,<'  ',(rule{::ElementIds),' by ',(','join names)
    end.
    conflicts =. I.conflict_counts>0
    lines =. lines,<'conflicts ',integer #conflicts
    for_i. conflicts do.
        pair =. i{::pairs
        'policy earlier later' =. pair
        winner =. conflict_winner pair
        lines =. lines,<'  ',(policy{::ElementIds),' ',(earlier{::ElementIds),' ',(later{::ElementIds),' ',(integer i{conflict_counts),' ',winner{::ElementIds
    end.
    lines
)
analysis_report =: 3 : 0
    lines =. <'rbac ',integer #RBACDiagnostics
    for_diagnostic. RBACDiagnostics do.
        'line keyword message' =. >diagnostic
        lines =. lines,<'  line ',(integer line),' ',keyword,' ',message
    end.
    grant_names =. 0$a:
    for_grant. Grants do.
        'role action kind' =. >grant
        grant_names =. grant_names,<(role{::RoleNames),' ',action,' ',kind
    end.
    lines =. lines,<'grants ',integer #Grants
    for_i. /:grant_names do.
        lines =. lines,<'  ',(i{::grant_names),' ',integer i{GrantCounts
    end.
    lines =. lines,domain_analysis ''
    lines =. lines,<'coverage ',integer #Requests
    uncovered =. i.0
    for_rule. RuleIndices do.
        symbols =. rule{::Coverage
        count =. +/symbols e.'PD'
        lines =. lines,<'  ',(rule{::ElementIds),' ',symbols,' ',integer count
        if. count=0 do.
            uncovered =. uncovered,rule
        end.
    end.
    lines =. lines,<'uncovered ',integer #uncovered
    for_rule. uncovered do.
        lines =. lines,<'  ',rule{::ElementIds
    end.
    lines =. lines,<'summary'
    names =. 'PERMIT';'DENY';'NOT_APPLICABLE';'INDETERMINATE';'ERROR'
    for_i. i.5 do.
        lines =. lines,<'  decision ',(i{::names),' ',integer i{DecisionCounts
    end.
    lines =. lines,<'  refused ',integer RefusedCount
    for_element. I.DecisiveCounts>0 do.
        lines =. lines,<'  decisive ',(element{::ElementIds),' ',integer element{DecisiveCounts
    end.
    for_kind. i.2 do.
        names =. ObligationNames
        counts =. ObligationCounts
        label =. 'obligation'
        if. kind=1 do.
            names =. AdviceNames
            counts =. AdviceCounts
            label =. 'advice'
        end.
        for_i. /:names do.
            lines =. lines,<'  ',label,' ',(i{::names),' ',integer i{counts
        end.
    end.
    lines
)
save =: 4 : 0
    text =. ''
    if. #y do.
        text =. (LF join y),LF
    end.
    text 1!:2 <'output/',x
)
run =: 3 : 0
    read_rbac ''
    read_policies ''
    read_attributes ''
    read_requests ''
    process_requests ''
    'decisions.txt'save DecisionLines
    'traces.txt'save TraceLines
    'permissions.txt'save permission_report ''
    'analysis.txt'save analysis_report ''
    i.0
)
run ''
