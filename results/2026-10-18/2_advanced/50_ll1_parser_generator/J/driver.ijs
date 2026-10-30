new_node =: 3 : '(<y),(<''''),<i.0'
parse_tokens =: 3 : 0
    'tokens positions model sets parse_table' =. y
    'order rules start' =. model
    'nullable first follow passes terminals' =. sets
    'productions predict reasons cells choices conflicts' =. parse_table
    input =. tokens,<'$'
    locations =. positions,1+#tokens
    tree =. ,<new_node start
    stack =. (<'$'),<start
    stack_nodes =. _1 0
    trace =. 0$a:
    left_parse =. i.0
    events =. 0$a:
    counts =. 6$0
    columns =. terminals,<'$'
    cursor =. 0
    step =. 0
    while. 1 do.
        step =. step+1
        top =. >{:stack
        node =. {:stack_nodes
        token =. cursor{::input
        before_stack =. ' 'join stack
        before_input =. ' 'join cursor}.input
        counts =. ((5{counts)>.#stack)5}counts
        action =. ''
        kind =. ''
        terminate =. 0
        if. (top-:'$')*.token-:'$' do.
            action =. 'accept'
            terminate =. 1
        elseif. top-:'$' do.
            action =. 'error: skip ',token
            kind =. 'skip'
        elseif. -.is_nt top do.
            stack =. }:stack
            stack_nodes =. }:stack_nodes
            if. top-:token do.
                action =. 'match ',token
                cursor =. cursor+1
                counts =. (1+1{counts)1}counts
            else.
                action =. 'error: missing ',top
                kind =. 'missing'
                record =. (<'missing')1}node{::tree
                tree =. (<record)node}tree
            end.
        else.
            lhs =. order i.<top
            column =. columns i.<token
            number =. (<lhs,column){choices
            if. number do.
                'unused_number unused_lhs rhs notation' =. (number-1){::productions
                action =. 'predict ',(number_text number),': ',notation
                left_parse =. left_parse,number
                counts =. (1+0{counts)0}counts
                stack =. }:stack
                stack_nodes =. }:stack_nodes
                children =. i.0
                if. 0=#rhs do.
                    children =. ,#tree
                    tree =. tree,<new_node '%empty'
                else.
                    for_symbol. rhs do.
                        children =. children,#tree
                        tree =. tree,<new_node >symbol
                    end.
                    stack =. stack,|.rhs
                    stack_nodes =. stack_nodes,|.children
                end.
                record =. (<children)2}node{::tree
                tree =. (<record)node}tree
            elseif. (token-:'$')+.(<token)e.lhs{::follow do.
                action =. 'error: pop ',top
                kind =. 'pop'
                record =. (<'error')1}node{::tree
                tree =. (<record)node}tree
                stack =. }:stack
                stack_nodes =. }:stack_nodes
            else.
                action =. 'error: skip ',token
                kind =. 'skip'
            end.
        end.
        if. #kind do.
            events =. events,<(<step),(<kind),(<top),(<token),<cursor{locations
            count_index =. 2+(;:'skip pop missing')i.<kind
            counts =. (1+count_index{counts)count_index}counts
            if. kind-:'skip' do.
                cursor =. cursor+1
            end.
        end.
        trace =. trace,<(<number_text step),(<before_stack),(<before_input),<action
        if. terminate do.
            break.
        end.
    end.
    (<tree),(<trace),(<left_parse),(<events),<counts
)
