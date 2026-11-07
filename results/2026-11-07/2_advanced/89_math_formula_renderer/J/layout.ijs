element_types =: 3 : 0
    node =. y{::NodePool
    'kind children value column' =. node
    select. kind
    case. 'symbol' do. type =. symbol_type value
    case. 'command' do. type =. command_type value
    case. 'delim' do. 4 5 return.
    case. 'script' do. element_types 0{children return.
    case. 'overset';'underset' do. element_types 1{children return.
    case. do. type =. 0
    end.
    type,type
)
converted_types =: 3 : 0
    types =. 0 2$0
    for_node. y do.
        types =. types,element_types node
    end.
    for_i. i.#y do.
        left =. (<i,0){types
        previous =. 0
        if. i>0 do.
            previous =. (<(i-1),1){types
        end.
        if. left=2 do.
            if. (i=0)+.previous e.2 1 3 4 6 do.
                types =. 0 i}types
            end.
        end.
        left =. (<i,0){types
        if. (left e.3 5 6)*.i>0 do.
            if. 2=(<(i-1),1){types do.
                types =. 0(i-1)}types
            end.
        end.
    end.
    if. #types do.
        if. 2=1{_1{types do.
            types =. 0((#types)-1)}types
        end.
    end.
    types
)
word_element =: 3 : 0
    'kind children value column' =. y{::NodePool
    if. kind-:'script' do.
        word_element 0{children
    elseif. kind-:'command' do.
        ((<}.value)e.GreekNames)+.value-:'\infty'
    else.
        0
    end.
)
alphanumeric_element =: 3 : 0
    'kind children value column' =. y{::NodePool
    if. ((<kind)e.'identifier';'number')+.word_element y do.
        1 return.
    end.
    if. kind-:'script' do.
        alphanumeric_element 0{children
    elseif. kind-:'accent' do.
        if. (<value)e.;:'overline hat vec dot tilde' do.
            alphanumeric_element 0{children
        else.
            0
        end.
    else.
        0
    end.
)
row_spacing =: 4 : 0
    style =. x
    nodes =. y
    types =. converted_types nodes
    table =. 0 1 _1 _2 0 0 0 1 1 _4 _2 0 0 0 _1 _1 _4 _4 _1 _4 _4
    table =. 7 7$table,_2 _2 _4 0 _2 0 0 0 0 _4 0 0 0 0 0 1 _1 _2 0 0 0 _3 _3 _4 _3 _3 _3 _3
    variable =. 0 0 0 0
    if. style-:'normal' do.
        variable =. 0,(parameter 'bin_space'),(parameter 'rel_space'),parameter 'punct_space'
    end.
    gaps =. i.0
    for_i. i.0>.(#nodes)-1 do.
        first =. i{nodes
        second =. (i+1){nodes
        if. (alphanumeric_element first)*.(alphanumeric_element second)*.(word_element first)+.word_element second do.
            gap =. 1
        else.
            right =. (<i,1){types
            left =. (<(i+1),0){types
            gap =. (<right,left){table
            if. gap<0 do.
                gap =. (-gap){variable
            end.
        end.
        gaps =. gaps,gap
    end.
    (<types),<gaps
)
assemble_row =: 3 : 0
    'children gaps description roles' =. y
    ascent =. 0
    descent =. 0
    width =. +/gaps
    for_child. children do.
        ascent =. ascent>.box_baseline child
        descent =. descent>.box_descent child
        width =. width+box_width child
    end.
    box =. new_box(<width),(<1+ascent+descent),(<ascent),<description
    position =. 0
    for_i. i.#children do.
        child =. i{children
        role =. i{::roles
        box add_child(<child),(<position),(<ascent-box_baseline child),<role
        position =. position+box_width child
        if. i<#gaps do.
            position =. position+i{gaps
        end.
    end.
    box
)
