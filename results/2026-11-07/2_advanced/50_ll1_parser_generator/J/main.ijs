load 'grammar_parser.ijs'
load 'transform.ijs'
load 'first_follow.ijs'
load 'll_table.ijs'
load 'driver.ijs'
read_lines =: 3 : '<;._2 (1!:1 <y)'
heading =: 4 : 0
    if. #y do.
        x,' ',' 'join y
    else.
        x
    end.
)
number_heading =: 4 : 'x heading number_text&.>y'
yes_no =: 3 : 'y{::;:''no yes'''
pair_less =: 4 : 0
    different =. I.x~:y
    if. #different do.
        index =. {.different
        (index{x)<index{y
    else.
        0
    end.
)
check_declarations =: 3 : 0
    'model diagnostics declared has_declarations word_names word_lines' =. y
    result =. 0$a:
    if. has_declarations do.
        for_name. /:~word_names-.declared do.
            line =. (word_names i.name){word_lines
            result =. result,<'undeclared terminal ',(>name),' at line ',number_text line
        end.
    end.
    result
)
reachable =: 3 : 0
    'order rules start' =. y
    initial =. order i.<start
    found =. (i.#order)=initial
    queue =. ,initial
    cursor =. 0
    while. cursor<#queue do.
        lhs =. cursor{queue
        cursor =. cursor+1
        for_rhs. lhs{::rules do.
            for_symbol. >rhs do.
                index =. order i.symbol
                if. index<#order do.
                    if. -.index{found do.
                        found =. 1 index}found
                        queue =. queue,index
                    end.
                end.
            end.
        end.
    end.
    found
)
filter_model =: 4 : 0
    'order rules start' =. y
    (<x#order),(<x#rules),<start
)
remove_alternatives =: 4 : 0
    'removed reason' =. x
    'order rules start' =. y
    diagnostics =. 0$a:
    for_lhs. i.#order do.
        retained =. 0$a:
        for_rhs. lhs{::rules do.
            rhs =. >rhs
            invalid =. rhs#~rhs e.removed
            if. #invalid do.
                text =. (lhs{::order)production_text rhs
                diagnostics =. diagnostics,<'removed ',text,' (',reason,' ',(0{::invalid),')'
            else.
                retained =. retained,<rhs
            end.
        end.
        rules =. (<retained)lhs}rules
    end.
    model =. (<order),(<rules),<start
    (<model),<diagnostics
)
clean_grammar =: 3 : 0
    'order rules start' =. y
    undefined =. 0$a:
    for_alternatives. rules do.
        for_rhs. >alternatives do.
            for_symbol. >rhs do.
                if. is_nt >symbol do.
                    if. -.symbol e.order do.
                        undefined =. undefined,symbol
                    end.
                end.
            end.
        end.
    end.
    inner =. /:~~.(}:@}.)&.>undefined
    undefined =. 0$a:
    diagnostics =. 0$a:
    for_name. inner do.
        name =. '<',(>name),'>'
        undefined =. undefined,<name
        diagnostics =. diagnostics,<'undefined nonterminal ',name
    end.
    'model removed_diags' =. ((<undefined),<'undefined')remove_alternatives y
    diagnostics =. diagnostics,removed_diags
    'order rules start' =. model
    productive =. (#order)$0
    changed =. 1
    while. changed do.
        changed =. 0
        for_lhs. i.#order do.
            if. lhs{productive do.
                continue.
            end.
            for_rhs. lhs{::rules do.
                valid =. 1
                for_symbol. >rhs do.
                    if. is_nt >symbol do.
                        if. -. (order i.symbol){productive do.
                            valid =. 0
                            break.
                        end.
                    end.
                end.
                if. valid do.
                    productive =. 1 lhs}productive
                    changed =. 1
                    break.
                end.
            end.
        end.
    end.
    unproductive =. (-.productive)#order
    for_name. unproductive do.
        diagnostics =. diagnostics,<'unproductive nonterminal ',>name
    end.
    model =. productive filter_model model
    'model removed_diags' =. ((<unproductive),<'unproductive')remove_alternatives model
    diagnostics =. diagnostics,removed_diags
    reached =. reachable model
    order =. 0{::model
    for_name. (-.reached)#order do.
        diagnostics =. diagnostics,<'unreachable nonterminal ',>name
    end.
    model =. reached filter_model model
    (<model),<diagnostics
)
left_recursion =: 3 : 0
    'order rules start' =. y
    diagnostics =. 0$a:
    for_initial. i.#order do.
        queue =. ,initial
        visited =. (i.#order)=initial
        parents =. (#order)$_1
        cursor =. 0
        found =. _1
        while. (cursor<#queue)*.found<0 do.
            lhs =. cursor{queue
            cursor =. cursor+1
            for_rhs. lhs{::rules do.
                rhs =. >rhs
                if. 0=#rhs do.
                    continue.
                end.
                symbol =. 0{rhs
                if. symbol-:initial{order do.
                    found =. lhs
                    break.
                end.
                next =. order i.symbol
                if. next<#order do.
                    if. -.next{visited do.
                        visited =. 1 next}visited
                        parents =. lhs next}parents
                        queue =. queue,next
                    end.
                end.
            end.
        end.
        if. found>:0 do.
            path =. initial{order
            current =. found
            while. current~:initial do.
                path =. (current{order),path
                current =. current{parents
            end.
            path =. (initial{order),path
            diagnostics =. diagnostics,<'left recursion: ',' -> 'join path
        end.
    end.
    diagnostics
)
final_pruning =: 3 : 0
    reached =. reachable y
    order =. 0{::y
    log =. 0$a:
    diagnostics =. 0$a:
    for_name. (-.reached)#order do.
        log =. log,<'remove unreachable ',>name
        diagnostics =. diagnostics,<'unreachable after transformation ',>name
    end.
    model =. reached filter_model y
    (<model),(<log),<diagnostics
)
unused_declarations =: 4 : 0
    'model diagnostics declared has_declarations word_names word_lines' =. x
    result =. 0$a:
    if. has_declarations do.
        known =. known_terminals 1{::y
        for_name. /:~declared-.known do.
            result =. result,<'unused token ',>name
        end.
    end.
    result
)
grammar_summary =: 3 : 0
    'order rules start' =. y
    count =. 0
    empty =. 0
    unit =. 0
    for_alternatives. rules do.
        for_rhs. >alternatives do.
            rhs =. >rhs
            count =. count+1
            empty =. empty+0=#rhs
            if. 1=#rhs do.
                unit =. unit+is_nt 0{::rhs
            end.
        end.
    end.
    'start=',start,' nonterminals=',(number_text #order),' terminals=',(number_text #known_terminals rules),' productions=',(number_text count),' empty=',(number_text empty),' unit=',number_text unit
)
grammar_listing =: 4 : 0
    'order rules start' =. y
    result =. 0$a:
    count =. 0
    width =. #number_text #number_productions y
    for_lhs. i.#order do.
        name =. lhs{::order
        alternatives =. lhs{::rules
        for_index. i.#alternatives do.
            count =. count+1
            prefix =. name,' -> '
            if. index do.
                prefix =. ((#name)$' '),' | '
            end.
            if. x do.
                text =. number_text count
                prefix =. ((width-#text)$' '),text,'  ',prefix
            end.
            result =. result,<prefix,alt_text index{::alternatives
        end.
    end.
    result
)
grammar_report =: 3 : 0
    'cleaned recursion factored final recursion_log factor_log final_log' =. y
    result =. (<'== cleaned grammar =='),(<grammar_summary cleaned),0 grammar_listing cleaned
    titles =. 'left recursion elimination';'left factoring';'final grammar'
    stages =. (<recursion),(<factored),<final
    logs =. (<recursion_log),(<factor_log),<final_log
    for_stage. i.3 do.
        result =. result,(<''),<'== ',(stage{::titles),' =='
        log =. stage{::logs
        if. 0=#log do.
            log =. <'none'
        end.
        model =. stage{::stages
        result =. result,log,(<grammar_summary model),(stage=2)grammar_listing model
    end.
    result =. result,(<''),<'== cross reference =='
    'order rules start' =. final
    productions =. number_productions final
    for_symbol. order,known_terminals rules do.
        symbol =. >symbol
        numbers =. i.0
        for_production. productions do.
            'number lhs rhs notation' =. >production
            if. (<symbol)e.rhs do.
                numbers =. numbers,number
            end.
        end.
        name =. symbol
        if. -.is_nt name do.
            name =. '"',name,'"'
        end.
        if. #numbers do.
            result =. result,<(name,' used in')number_heading numbers
        else.
            result =. result,<name,' not used'
        end.
    end.
    result
)
sequence_score =: 4 : 0
    'order scores' =. x
    length =. 0x
    height =. 0
    for_symbol. y do.
        if. is_nt >symbol do.
            score =. (order i.symbol){scores
            if. (0{score)<0 do.
                0 0 0 return.
            end.
            length =. length+0{score
            height =. height>.1{score
        else.
            length =. length+1
        end.
    end.
    length,(height+1),1
)
expand_sentence =: 3 : 0
    if. -.is_nt y do.
        ,<y return.
    end.
    index =. SentenceOrder i.<y
    if. -.index{SentenceReady do.
        value =. 0$a:
        for_child. index{::SentenceSelected do.
            value =. value,expand_sentence >child
        end.
        Sentences =: (<value)index}Sentences
        SentenceReady =: 1 index}SentenceReady
    end.
    index{::Sentences
)
shortest_sentences =: 3 : 0
    'order rules start' =. y
    scores =. ((#order),2)$_1x
    changed =. 1
    while. changed do.
        changed =. 0
        for_lhs. i.#order do.
            for_rhs. lhs{::rules do.
                score =. ((<order),<scores)sequence_score >rhs
                if. 2{score do.
                    key =. 2{.score
                    if. ((0{lhs{scores)<0)+.key pair_less lhs{scores do.
                        scores =. key lhs}scores
                        changed =. 1
                    end.
                end.
            end.
        end.
    end.
    selected =. 0$a:
    for_lhs. i.#order do.
        for_rhs. lhs{::rules do.
            score =. ((<order),<scores)sequence_score >rhs
            if. 2{score do.
                if. (2{.score)-:lhs{scores do.
                    selected =. selected,rhs
                    break.
                end.
            end.
        end.
    end.
    SentenceOrder =: order
    SentenceSelected =: selected
    Sentences =: (#order)$<0$a:
    SentenceReady =: (#order)$0
    for_lhs. order do.
        expand_sentence >lhs
    end.
    (<scores),<Sentences
)
sentence =: 4 : 0
    'order sentences' =. x
    result =. 0$a:
    for_symbol. y do.
        if. is_nt >symbol do.
            result =. result,(order i.symbol){::sentences
        else.
            result =. result,symbol
        end.
    end.
    result
)
build_context =: 3 : 0
    if. y{ContextReady do.
        i.0 return.
    end.
    'number position lhs' =. y{ContextParents
    build_context lhs
    rhs =. (number-1){::ContextBodies
    sentence_args =. (<ContextOrder),<ContextSentences
    prefix =. (lhs{::ContextPrefixes),sentence_args sentence position{.rhs
    suffix =. (sentence_args sentence (position+1)}.rhs),lhs{::ContextSuffixes
    ContextPrefixes =: (<prefix)y}ContextPrefixes
    ContextSuffixes =: (<suffix)y}ContextSuffixes
    ContextReady =: 1 y}ContextReady
    i.0
)
shortest_contexts =: 3 : 0
    'model scores sentences productions' =. y
    'order rules start' =. model
    costs =. ((#order),2)$_1x
    parents =. ((#order),3)$_1
    initial =. order i.<start
    costs =. 0 0 initial}costs
    changed =. 1
    while. changed do.
        changed =. 0
        for_production. productions do.
            'number lhs rhs notation' =. >production
            if. (0{lhs{costs)<0 do.
                continue.
            end.
            for_position. i.#rhs do.
                symbol =. position{::rhs
                if. (-.is_nt symbol)+.symbol-:start do.
                    continue.
                end.
                index =. order i.<symbol
                outside =. (position{.rhs),(position+1)}.rhs
                score =. ((<order),<scores)sequence_score outside
                cost =. ((0{lhs{costs)+0{score),1+1{lhs{costs
                key =. number,position
                better =. (0{index{costs)<0
                better =. better+.cost pair_less index{costs
                if. cost-:index{costs do.
                    better =. better+.key pair_less 2{.index{parents
                end.
                if. better do.
                    costs =. cost index}costs
                    parents =. (number,position,lhs)index}parents
                    changed =. 1
                end.
            end.
        end.
    end.
    ContextOrder =: order
    ContextParents =: parents
    ContextBodies =: 2&{::&.>productions
    ContextSentences =: sentences
    ContextPrefixes =: (#order)$<0$a:
    ContextSuffixes =: (#order)$<0$a:
    ContextReady =: (i.#order)=initial
    for_index. i.#order do.
        build_context index
    end.
    (<ContextPrefixes),<ContextSuffixes
)
sets_report =: 3 : 0
    'model sets sentences' =. y
    'order rules start' =. model
    'nullable first follow passes terminals' =. sets
    result =. (<'passes: nullable=',(number_text 0{passes),' first=',(number_text 1{passes),' follow=',number_text 2{passes),<''
    for_lhs. i.#order do.
        result =. result,lhs{order
        result =. result,<'  nullable: ',yes_no lhs{nullable
        result =. result,<'  first:'heading terminal_order lhs{::first
        result =. result,<'  follow:'heading terminal_order lhs{::follow
        result =. result,<'  shortest:'heading lhs{::sentences
    end.
    result
)
first_path =: 3 : 0
    'initial token model sets parse_table' =. y
    order =. 0{::model
    nullable =. 0{::sets
    productions =. 0{::parse_table
    queue =. ,initial
    visited =. (1+i.#productions)=initial
    parents =. (#productions)$_1
    cursor =. 0
    while. cursor<#queue do.
        current =. cursor{queue
        cursor =. cursor+1
        rhs =. 2{::(current-1){::productions
        for_symbol. rhs do.
            symbol =. >symbol
            if. symbol-:token do.
                path =. i.0
                while. current~:initial do.
                    path =. current,path
                    current =. (current-1){parents
                end.
                path return.
            end.
            if. is_nt symbol do.
                lhs =. order i.<symbol
                for_production. productions do.
                    'number owner body notation' =. >production
                    if. owner=lhs do.
                        if. -. (number-1){visited do.
                            visited =. 1 (number-1)}visited
                            parents =. current (number-1)}parents
                            queue =. queue,number
                        end.
                    end.
                end.
                if. -.lhs{nullable do.
                    break.
                end.
            else.
                break.
            end.
        end.
    end.
    i.0
)
follow_path =: 3 : 0
    'initial token model sets parse_table' =. y
    'order rules start' =. model
    'nullable first follow passes terminals' =. sets
    productions =. 0{::parse_table
    queue =. ,initial
    visited =. (i.#order)=initial
    paths =. (#order)$<i.0
    cursor =. 0
    while. cursor<#queue do.
        symbol =. cursor{queue
        cursor =. cursor+1
        path =. symbol{::paths
        if. ((symbol{::order)-:start)*.token-:'$' do.
            path return.
        end.
        for_production. productions do.
            'number lhs rhs notation' =. >production
            for_position. i.#rhs do.
                if. -. (position{rhs)-:symbol{order do.
                    continue.
                end.
                suffix =. (position+1)}.rhs
                'more empty' =. ((<order),(<nullable),<first)first_sequence suffix
                extended =. path,number
                if. (<token)e.more do.
                    extended return.
                end.
                if. empty*.-.lhs{visited do.
                    visited =. 1 lhs}visited
                    paths =. (<extended)lhs}paths
                    queue =. queue,lhs
                end.
            end.
        end.
    end.
    i.0
)
table_report =: 3 : 0
    'model sets parse_table conflicts_before' =. y
    'order rules start' =. model
    'nullable first follow passes terminals' =. sets
    'productions predict reasons cells choices conflicts' =. parse_table
    result =. <'== predict sets =='
    for_index. i.#productions do.
        'number lhs rhs notation' =. index{::productions
        result =. result,<(number_text number),': ',notation
        result =. result,<'  predict:'heading index{::predict
    end.
    result =. result,(<''),<'== parse table =='
    columns =. terminals,<'$'
    matrix =. ,<(<''),columns
    for_lhs. i.#order do.
        row =. lhs{order
        for_column. i.#columns do.
            numbers =. >(<lhs,column){cells
            text =. '.'
            if. #numbers do.
                text =. '/'join number_text&.>numbers
            end.
            row =. row,<text
        end.
        matrix =. matrix,<row
    end.
    widths =. (1+#columns)$0
    for_row. matrix do.
        widths =. widths>.#&>>row
    end.
    for_box. matrix do.
        row =. >box
        value =. 0{::row
        line =. value,((0{widths)-#value)$' '
        for_column. }.i.#row do.
            value =. column{::row
            line =. line,'  ',(((column{widths)-#value)$' '),value
        end.
        result =. result,<line
    end.
    result =. result,(<''),<'== conflicts =='
    if. 0=#conflicts do.
        result =. result,<'none'
    end.
    for_conflict. conflicts do.
        'lhs column numbers kind chosen' =. >conflict
        token =. column{::columns
        result =. result,<'conflict ',(lhs{::order),' on ',token,': ',kind,', chosen ',number_text chosen
        for_number. numbers do.
            production =. (number-1){::productions
            index =. ((number-1){::predict)i.<token
            reason =. index{::(number-1){::reasons
            args =. (<number),(<token),(<model),(<sets),<parse_table
            if. reason-:'FIRST' do.
                path =. first_path args
            else.
                args =. (<lhs),(<token),(<model),(<sets),<parse_table
                path =. follow_path args
            end.
            if. #path do.
                reason =. (reason,' via')number_heading path
            end.
            result =. result,<'  ',(number_text number),': ',(3{::production),' (',reason,')'
        end.
    end.
    result =. result,<'LL(1): ',yes_no 0=#conflicts
    result,<'conflicts before transformation: ',number_text conflicts_before
)
compact_node =: 3 : 0
    'symbol mark original_children' =. y{::OriginalTree
    children =. i.0
    for_child_index. original_children do.
        original_child =. child_index{::OriginalTree
        if. '%empty'-:0{::original_child do.
            continue.
        end.
        compacted =. compact_node child_index
        'child_symbol child_mark child_children' =. compacted{::CompactNodes
        if. is_nt child_symbol do.
            if. 0=#child_mark do.
                if. 0=#child_children do.
                    continue.
                elseif. +./child_symbol='''' do.
                    children =. children,child_children
                    continue.
                end.
            end.
        end.
        children =. children,compacted
    end.
    if. (1=#children)*.0=#mark do.
        {.children return.
    end.
    index =. #CompactNodes
    CompactNodes =: CompactNodes,<(<symbol),(<mark),<children
    index
)
tree_label =: 3 : 0
    'symbol mark children' =. y
    if. #mark do.
        symbol,' (',mark,')'
    else.
        symbol
    end.
)
draw_child =: 3 : 0
    'index prefix last' =. y
    record =. index{::DrawNodes
    branch =. '|-- '
    extension =. '|   '
    if. last do.
        branch =. '`-- '
        extension =. '    '
    end.
    TreeLines =: TreeLines,<prefix,branch,tree_label record
    children =. 2{::record
    for_i. i.#children do.
        draw_child (<i{children),(<prefix,extension),<i=<:#children
    end.
    i.0
)
tree_lines =: 3 : 0
    'DrawNodes root' =: y
    TreeLines =: <tree_label root{::DrawNodes
    children =. 2{::root{::DrawNodes
    for_i. i.#children do.
        draw_child (<i{children),(<''),<i=<:#children
    end.
    TreeLines
)
trace_lines =: 3 : 0
    header =. 'step';'stack';'input';'action'
    rows =. (<header),y
    widths =. 0 0 0
    for_row. rows do.
        widths =. widths>.3{.#&>>row
    end.
    result =. 0$a:
    for_box. rows do.
        row =. >box
        line =. ''
        for_i. i.3 do.
            value =. i{::row
            line =. line,value,(((i{widths)-#value)$' '),'  '
        end.
        result =. result,<line,3{::row
    end.
    result
)
leftmost_derivation =: 3 : 0
    'model numbers productions' =. y
    start =. 2{::model
    symbols =. ,<start
    result =. <'  ',start
    for_number. numbers do.
        position =. 0
        while. -.is_nt position{::symbols do.
            position =. position+1
        end.
        rhs =. 2{::(number-1){::productions
        symbols =. (position{.symbols),rhs,(position+1)}.symbols
        result =. result,<'  => ',alt_text symbols
    end.
    result
)
add_state =: 4 : 0
    items =. x{::Chart
    if. -. (<y)e.<"1 items do.
        Chart =: (<items,y)x}Chart
    end.
    i.0
)
language =: 4 : 0
    'order rules start' =. x
    tokens =. y
    productions =. number_productions x
    lhs_names =. ,<''
    bodies =. ,<,<start
    by_lhs =. (#order)$<i.0
    for_production. productions do.
        'number lhs rhs notation' =. >production
        lhs_names =. lhs_names,lhs{order
        bodies =. bodies,<rhs
        held =. lhs{::by_lhs
        by_lhs =. (<held,number)lhs}by_lhs
    end.
    Chart =: (1+#tokens)$<0 3$0
    0 add_state 0 0 0
    for_position. i.1+#tokens do.
        cursor =. 0
        while. cursor<#position{::Chart do.
            'number dot origin' =. cursor{position{::Chart
            cursor =. cursor+1
            rhs =. number{::bodies
            if. dot=#rhs do.
                prior =. origin{::Chart
                for_waiting. prior do.
                    'parent consumed begin' =. waiting
                    body =. parent{::bodies
                    if. consumed<#body do.
                        if. (consumed{body)-:number{lhs_names do.
                            position add_state parent,(consumed+1),begin
                        end.
                    end.
                end.
            else.
                symbol =. dot{::rhs
                if. is_nt symbol do.
                    lhs =. order i.<symbol
                    for_child. lhs{::by_lhs do.
                        position add_state child,0,position
                    end.
                    completed =. position{::Chart
                    for_candidate. completed do.
                        'child consumed begin' =. candidate
                        if. ((child{::lhs_names)-:symbol)*.(consumed=#child{::bodies)*.begin=position do.
                            position add_state number,(dot+1),origin
                        end.
                    end.
                elseif. position<#tokens do.
                    if. (dot{rhs)-:position{tokens do.
                        (position+1)add_state number,(dot+1),origin
                    end.
                end.
            end.
        end.
    end.
    (<0 1 0)e.<"1 (#tokens){::Chart
)
event_error =: 4 : 0
    'model sets parse_table' =. x
    'step kind symbol token position' =. y
    order =. 0{::model
    terminals =. 4{::sets
    choices =. 4{::parse_table
    unexpected =. 'end of input'
    if. -.token-:'$' do.
        unexpected =. '"',token,'" at token ',number_text position
    end.
    if. is_nt symbol do.
        lhs =. order i.<symbol
        columns =. terminals,<'$'
        names =. 0$a:
        for_column. i.#columns do.
            if. (<lhs,column){choices do.
                name =. column{::columns
                if. -.name-:'$' do.
                    name =. '"',name,'"'
                end.
                names =. names,<name
            end.
        end.
        expected =. ' 'join names
    elseif. symbol-:'$' do.
        expected =. '$'
    else.
        expected =. '"',symbol,'"'
    end.
    select. kind
    case. 'skip' do.
        recovery =. 'skipped "',token,'"'
    case. 'pop' do.
        recovery =. 'popped ',symbol
    case. 'missing' do.
        recovery =. 'inserted "',symbol,'"'
    end.
    'step ',(number_text step),': unexpected ',unexpected,'; expected ',expected,'; ',recovery
)
parse_input =: 4 : 0
    'model cleaned sets parse_table' =. x
    known =. 4{::sets
    kept =. 0$a:
    positions =. i.0
    errors =. 0$a:
    for_i. i.#y do.
        token =. i{y
        if. token e.known do.
            kept =. kept,token
            positions =. positions,i+1
        else.
            errors =. errors,<'unknown "',(>token),'" at token ',(number_text i+1),'; removed'
        end.
    end.
    unknown =. #errors
    parsed =. parse_tokens (<kept),(<positions),(<model),(<sets),<parse_table
    args =. (<model),(<sets),<parse_table
    for_event. 3{::parsed do.
        errors =. errors,<args event_error >event
    end.
    accepted =. 0=#errors
    in_language =. cleaned language y
    (<parsed),(<y),(<errors),(<unknown),(<accepted),<in_language
)
one_parse =: 4 : 0
    number =. x
    'input model parse_table' =. y
    'parsed original errors unknown accepted in_language' =. input
    'tree trace left_parse events counts' =. parsed
    productions =. 0{::parse_table
    result =. (<'== input ',(number_text number),' =='),<'tokens:'heading original
    result =. result,trace_lines trace
    result =. result,<'left parse:'number_heading left_parse
    result =. result,<'stats: steps=',(number_text #trace),' predicts=',(number_text 0{counts),' matches=',(number_text 1{counts),' max_stack=',number_text 5{counts
    if. #errors do.
        result =. result,<'errors:'
        for_message. errors do.
            result =. result,<'  ',>message
        end.
    end.
    status =. 'result: accepted'
    if. -.accepted do.
        status =. 'result: rejected (errors: ',(number_text #errors),')'
    end.
    result =. result,(<status),<'language: ',yes_no in_language
    if. accepted do.
        result =. result,<'derivation:'
        result =. result,leftmost_derivation (<model),(<left_parse),<productions
    end.
    result =. result,<'tree:'
    result =. result,tree_lines (<tree),<0
    result =. result,<'compact tree:'
    OriginalTree =: tree
    CompactNodes =: 0$a:
    root =. compact_node 0
    result,tree_lines (<CompactNodes),<root
)
parse_report =: 3 : 0
    'inputs model sets parse_table sentences context' =. y
    'prefixes suffixes' =. context
    order =. 0{::model
    productions =. 0{::parse_table
    result =. 0$a:
    accepted_count =. 0
    in_language_count =. 0
    mismatches =. i.0
    used =. i.0
    recovery =. 0 0 0 0
    for_i. i.#inputs do.
        input =. i{::inputs
        'parsed original errors unknown accepted in_language' =. input
        result =. result,(i+1)one_parse (<input),(<model),<parse_table
        result =. result,<''
        accepted_count =. accepted_count+accepted
        in_language_count =. in_language_count+in_language
        if. accepted~:in_language do.
            mismatches =. mismatches,i+1
        end.
        counts =. 4{::parsed
        recovery =. recovery+unknown,2 3 4{counts
        used =. ~.used,2{::parsed
    end.
    unused =. (1+i.#productions)-.used
    result =. result,<'== summary =='
    result =. result,<'inputs=',(number_text #inputs),' accepted=',(number_text accepted_count),' rejected=',(number_text (#inputs)-accepted_count),' in_language=',number_text in_language_count
    result =. result,<'mismatches:'number_heading mismatches
    result =. result,<'recovery: unknown=',(number_text 0{recovery),' skip=',(number_text 1{recovery),' pop=',(number_text 2{recovery),' missing=',number_text 3{recovery
    result =. result,<'coverage: ',(number_text #used),' of ',(number_text #productions),' productions used'
    result =. result,<'unused:'number_heading unused
    sentence_args =. (<order),<sentences
    for_number. unused do.
        'unused_number lhs rhs notation' =. (number-1){::productions
        example =. (lhs{::prefixes),(sentence_args sentence rhs),lhs{::suffixes
        positions =. 1+i.#example
        parsed =. parse_tokens (<example),(<positions),(<model),(<sets),<parse_table
        events =. 3{::parsed
        status =. '    result: accepted'
        if. #events do.
            status =. '    result: rejected (errors: ',(number_text #events),')'
        end.
        result =. result,<'  ',(number_text number),': ',notation
        result =. result,<'    example:'heading example
        result =. result,<status
        result =. result,<'    used: ',yes_no number e.2{::parsed
    end.
    result
)
save =: 4 : 0
    ((LF join y),LF)1!:2 <'output/',x
)
run =: 3 : 0
    source =. parse_grammar read_lines 'input/grammar.bnf'
    declarations =. check_declarations source
    'cleaned clean_diags' =. clean_grammar 0{::source
    recursion_diags =. left_recursion cleaned
    'recursion recursion_log' =. eliminate_recursion cleaned
    'factored factor_log' =. left_factor recursion
    'final final_log final_diags' =. final_pruning factored
    before_sets =. analyze_sets cleaned
    before_table =. cleaned build_table before_sets
    sets =. analyze_sets final
    parse_table =. final build_table sets
    'scores sentences' =. shortest_sentences final
    productions =. 0{::parse_table
    context =. shortest_contexts (<final),(<scores),(<sentences),<productions
    inputs =. 0$a:
    args =. (<final),(<cleaned),(<sets),<parse_table
    for_line. read_lines 'input/inputs.txt' do.
        tokens =. 0$a:
        if. #>line do.
            tokens =. <;._1 ' ',>line
        end.
        inputs =. inputs,<args parse_input tokens
    end.
    diagnostics =. (1{::source),declarations,clean_diags,recursion_diags,final_diags,source unused_declarations final
    conflicts =. 5{::parse_table
    status =. 'result: LL(1)'
    if. #conflicts do.
        status =. 'result: not LL(1) (conflicts: ',(number_text #conflicts),')'
    end.
    diagnostics =. diagnostics,<status
    grammar_args =. (<cleaned),(<recursion),(<factored),(<final),(<recursion_log),(<factor_log),<final_log
    'grammar.txt'save grammar_report grammar_args
    'sets.txt'save sets_report (<final),(<sets),<sentences
    'table.txt'save table_report (<final),(<sets),(<parse_table),<#5{::before_table
    'parses.txt'save parse_report (<inputs),(<final),(<sets),(<parse_table),(<sentences),<context
    'diagnostics.txt'save diagnostics
    i.0
)
run ''
