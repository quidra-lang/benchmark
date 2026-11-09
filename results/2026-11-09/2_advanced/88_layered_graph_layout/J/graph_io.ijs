SettingNames =: ;:'layering width promotion heuristic sweeps node_sep dummy_sep layer_gap direction sifting reduce restarts seed'
DefaultSettings =: (<'longest'),(<4),(<'off'),(<'barycenter'),(<12),(<2),(<1),(<3),(<'TB'),(<'off'),(<'off'),(<0),<1
SettingRanges =: 13 2$0 0 1 40 0 0 0 0 0 50 1 9 1 9 2 9 0 0 0 0 0 0 0 9 1 2147483646
IntegerSettings =: 1 4 5 6 7 11 12
setting_value =: 4 : 0
    name =. x
    word =. y
    index =. SettingNames i.<name
    if. index=#SettingNames do.
        (<0),<0 return.
    end.
    if. index e.IntegerSettings do.
        if. (0=#word)+.10<#word do.
            (<0),<0 return.
        end.
        if. -.*/word e.'0123456789' do.
            (<0),<0 return.
        end.
        value =. parse_integer word
        'low high' =. index{SettingRanges
        (<(value>:low)*.value<:high),<value
    else.
        select. index
        case. 0 do. choices =. ;:'longest coffman'
        case. 2;9;10 do. choices =. ;:'on off'
        case. 3 do. choices =. ;:'barycenter median'
        case. 8 do. choices =. ;:'TB BT LR RL'
        end.
        (<(<word)e.choices),<word
    end.
)
input_records =: 3 : 0
    result =. 0$a:
    lines =. <;._2 (1!:1 <'input/',y)
    for_i. i.#lines do.
        line =. i{::lines
        if. 0=#line do.
            continue.
        end.
        if. '#'~:{.line do.
            result =. result,<( <i+1),<split_words line
        end.
    end.
    result
)
read_defaults =: 3 : 0
    for_record. input_records 'params.txt' do.
        fields =. 1{::>record
        'name word' =. fields
        'valid value' =. name setting_value word
        index =. SettingNames i.<name
        DefaultSettings =: (<value)index}DefaultSettings
    end.
)
read_graphs =: 3 : 0
    Graphs =: 0$a:
    for_record. input_records 'graphs.txt' do.
        'line fields' =. >record
        kind =. 0{::fields
        if. kind-:'GRAPH' do.
            name =. 1{::fields
            settings =. DefaultSettings
            ids =. i.0
            labels =. 0$a:
            edges =. 0 2$0
            path =. i.0
            self_loops =. 0
            duplicates =. 0
            error =. ''
            error_line =. 0
        elseif. kind-:'END' do.
            if. (0=#error)*.0=#ids do.
                error =. 'no_nodes'
                error_line =. line
            end.
            graph =. (<name),(<settings),(<ids),(<labels),(<edges),(<path)
            graph =. graph,(<self_loops),(<duplicates),(<error),<error_line
            Graphs =: Graphs,<graph
        elseif. #error do.
            continue.
        elseif. kind-:'OPTION' do.
            'option word' =. }.fields
            'valid value' =. option setting_value word
            if. valid do.
                index =. SettingNames i.<option
                settings =. (<value)index}settings
            else.
                error =. 'bad_option'
                error_line =. line
            end.
        elseif. kind-:'NODE' do.
            id =. parse_integer 1{::fields
            if. id e.ids do.
                error =. 'duplicate_node'
            elseif. 40=#ids do.
                error =. 'too_many_nodes'
            else.
                ids =. ids,id
                labels =. labels,<2{::fields
            end.
            if. #error do.
                error_line =. line
            end.
        else.
            'first second' =. parse_integer&>}.fields
            if. -.*/(first,second)e.ids do.
                error =. 'unknown_node'
                error_line =. line
            elseif. kind-:'PATH' do.
                path =. first,second
            elseif. first=second do.
                self_loops =. self_loops+1
            elseif. +./(first,second)-:"1 edges do.
                duplicates =. duplicates+1
            else.
                edges =. edges,first,second
            end.
        end.
    end.
)
setting =: 3 : '(SettingNames i.<y){::Settings'
