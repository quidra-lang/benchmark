new_value =: 4 : 0
    number =. #Values
    Values =: Values,<(<x),<y
    number
)
value_kind =: 3 : '0{::y{::Values'
value_data =: 3 : '1{::y{::Values'
new_environment =: 3 : 0
    number =. #ValueEnvironments
    ValueEnvironments =: ValueEnvironments,<y
    number
)
runtime_fail =: 4 : 0
    RuntimeError =: (<x),<y
    13!:8 3
)
checked_integer =: 4 : 0
    if. (y<_2147483648x)+.y>2147483647x do. x runtime_fail 'integer overflow' end.
    y
)
compare_strings =: 4 : 0
    for_i. i.(#x)<.#y do.
        first =. a.i.i{x
        second =. a.i.i{y
        if. first~:second do. (first>second)-first<second return. end.
    end.
    ((#x)>#y)-(#x)<#y
)
compare_values =: 3 : 0
    'first second position' =. y
    kind =. value_kind first
    if. (<kind)e.'closure';'builtin' do. position runtime_fail 'functional value compared' end.
    a =. value_data first
    b =. value_data second
    if. (<kind)e.'pair';'list' do.
        for_i. i.(#a)<.#b do.
            order =. compare_values(<i{a),(<i{b),<position
            if. order do. order return. end.
        end.
        ((#a)>#b)-(#a)<#b
    elseif. kind-:'string' do.
        a compare_strings b
    else.
        (a>b)-a<b
    end.
)
evaluate_binary =: 3 : 0
    'operator first second position' =. y
    a =. value_data first
    b =. value_data second
    if. 1=#operator do. operator =. {.operator end.
    select. operator
    case. '+' do. 'integer'new_value position checked_integer a+b return.
    case. '-' do. 'integer'new_value position checked_integer a-b return.
    case. '*' do. 'integer'new_value position checked_integer a*b return.
    case. '/';'mod' do.
        if. b=0 do. position runtime_fail 'division by zero' end.
        quotient =. <.(x:|a)%x:|b
        if. (a<0)~:b<0 do. quotient =. -quotient end.
        if. operator-:'/' do.
            'integer'new_value position checked_integer quotient return.
        else.
            'integer'new_value a-b*quotient return.
        end.
    case. '^' do. 'string'new_value a,b return.
    case. '::' do. 'list'new_value first,b return.
    end.
    order =. compare_values(<first),(<second),<position
    select. operator
    case. '=' do. result =. order=0
    case. '<>' do. result =. order~:0
    case. '<' do. result =. order<0
    case. '>' do. result =. order>0
    case. '<=' do. result =. order<:0
    case. '>=' do. result =. order>:0
    end.
    'boolean'new_value result
)
match_pattern =: 4 : 0
    number =. x
    'kind position children value inferred' =. y{::Nodes
    data =. value_data number
    if. kind-:'wildcard' do. 1 return. end.
    if. kind-:'name' do.
        EvalPatternBindings =: ((<value),<number)env_put EvalPatternBindings
        1 return.
    end.
    if. (<kind)e.;:'integer boolean string' do. value-:data return. end.
    if. kind-:'cons' do.
        if. 0=#data do. 0 return. end.
        if. -.({.data)match_pattern 0{children do. 0 return. end.
        ('list'new_value }.data)match_pattern 1{children return.
    end.
    if. (#data)~:#children do. 0 return. end.
    for_i. i.#children do.
        if. -.(i{data)match_pattern i{children do. 0 return. end.
    end.
    1
)
evaluate_expression =: 4 : 0
    environment =. x
    'kind position children value inferred' =. y{::Nodes
    select. kind
    case. 'integer';'boolean';'string' do. kind new_value value
    case. 'name' do.
        records =. environment{::ValueEnvironments
        1{::(value env_index records){::records
    case. 'fun' do.
        'closure'new_value(<1{::value),(<{.children),<environment
    case. 'apply' do.
        function =. environment evaluate_expression 0{children
        argument =. environment evaluate_expression 1{children
        FileCalls =: FileCalls+1
        if. 'builtin'-:value_kind function do.
            position builtin_call(<value_data function),<argument
        else.
            'parameter body closure_environment' =. value_data function
            inner =. closure_environment{::ValueEnvironments
            if. -.parameter-:,'_' do.
                inner =. ((<parameter),<argument)env_put inner
            end.
            (new_environment inner)evaluate_expression body
        end.
    case. 'binary' do.
        first =. environment evaluate_expression 0{children
        operator =. 1{::value
        if. operator-:'&&' do.
            if. value_data first do. environment evaluate_expression 1{children else. first end.
        elseif. operator-:'||' do.
            if. value_data first do. first else. environment evaluate_expression 1{children end.
        else.
            second =. environment evaluate_expression 1{children
            evaluate_binary(<operator),(<first),(<second),<3{::value
        end.
    case. 'negate' do.
        first =. environment evaluate_expression 0{children
        'integer'new_value(3{::value)checked_integer -value_data first
    case. 'if' do.
        condition =. environment evaluate_expression 0{children
        selected =. (2-value_data condition){children
        environment evaluate_expression selected
    case. 'pair';'list' do.
        values =. i.0
        for_child. children do. values =. values,environment evaluate_expression child end.
        kind new_value values
    case. 'match' do.
        matched =. environment evaluate_expression 0{children
        found =. 0
        for_arm. value do.
            'pattern expression' =. arm
            EvalPatternBindings =: 0$a:
            if. matched match_pattern pattern do.
                inner =. environment{::ValueEnvironments
                for_record. EvalPatternBindings do. inner =. (>record)env_put inner end.
                (new_environment inner)evaluate_expression expression return.
            end.
        end.
        position runtime_fail 'match failure'
    case. 'let' do.
        inner =. environment evaluate_group value
        inner evaluate_expression 0{children
    end.
)
evaluate_group =: 4 : 0
    environment =. x
    'bindings rec_position' =. y{::Groups
    inner =. environment{::ValueEnvironments
    if. #rec_position do.
        result =. new_environment inner
        for_number. bindings do.
            'name position expression scheme classification' =. number{::Bindings
            'kind expression_position children token inferred' =. expression{::Nodes
            closure =. 'closure'new_value(<1{::token),(<{.children),<result
            inner =. ((<name),<closure)env_put inner
        end.
        ValueEnvironments =: (<inner)result}ValueEnvironments
        result
    else.
        values =. i.0
        for_number. bindings do.
            values =. values,environment evaluate_expression 2{::number{::Bindings
        end.
        for_i. i.#bindings do.
            name =. 0{::(i{bindings){::Bindings
            inner =. ((<name),<i{values)env_put inner
        end.
        new_environment inner
    end.
)
