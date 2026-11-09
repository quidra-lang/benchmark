split_on =: 4 : 0
    remaining =. y
    result =. 0$a:
    while. 1 do.
        positions =. I.x E.remaining
        if. 0=#positions do.
            result,<remaining return.
        end.
        position =. {.positions
        result =. result,<position{.remaining
        remaining =. (position+#x)}.remaining
    end.
)
f_name =: 0&{::
f_column =: 1&{::
f_power =: 2&{::
f_categorical =: 3&{::
t_factors =: 0&{::
t_name =: 1&{::
t_keys =: 2&{::
model_original =: 0&{::
model_response =: 1&{::
model_response_column =: 2&{::
model_weight =: 3&{::
model_weight_column =: 4&{::
model_terms =: 5&{::
model_factor_columns =: 6&{::
model_categorical_columns =: 7&{::
model_variables =: 8&{::
column_term =: 0&{::
column_name =: 1&{::
column_components =: 2&{::
component_factor =: 0&{::
component_name =: 1&{::
component_level =: 2&{::
d_model =: 0&{::
d_row_numbers =: 1&{::
d_rows =: 2&{::
d_levels =: 3&{::
d_columns =: 4&{::
d_matrix =: 5&{::
d_response =: 6&{::
d_weights =: 7&{::
parse_factor =: 4 : 0
    name =. y
    categorical =. 'C('-:2{.name
    column =. name
    power =. 1
    if. categorical do.
        column =. 2}.}:name
    elseif. 'I('-:2{.name do.
        parts =. '^'split_on 2}.}:name
        column =. 0{::parts
        power =. <.decimal 1{::parts
    end.
    (<name),(<x i.<column),(<power),<categorical
)
make_term =: 3 : 0
    names =. f_name&.>y
    name =. ''
    for_index. i.#names do.
        if. index do.
            name =. name,':'
        end.
        name =. name,index{::names
    end.
    (<y),(<name),</:~names
)
contained =: 4 : 0
    if. (#t_factors x)>:#t_factors y do.
        0 return.
    end.
    *./(t_keys x)e.t_keys y
)
parse_model =: 4 : 0
    parts =. ' weights='split_on y
    original =. 0{::parts
    weight =. ''
    if. 2=#parts do.
        weight =. 1{::parts
    end.
    halves =. ' ~ 'split_on original
    terms =. 0$a:
    factor_columns =. i.0
    categorical_columns =. i.0
    variables =. i.0
    for_box. ' + 'split_on 1{::halves do.
        expression =. >box
        expanded =. 0$a:
        if. '*'e.expression do.
            factors =. 0$a:
            for_name. '*'split_on expression do.
                factors =. factors,<x parse_factor >name
            end.
            for_size. 1+i.#factors do.
                for_mask. 1+i.(2^#factors)-1 do.
                    chosen =. factors#~2|<.mask%2^i.#factors
                    if. size=#chosen do.
                        expanded =. expanded,<chosen
                    end.
                end.
            end.
        else.
            factors =. 0$a:
            for_name. ':'split_on expression do.
                factors =. factors,<x parse_factor >name
            end.
            expanded =. <factors
        end.
        for_box. expanded do.
            factors =. >box
            item =. make_term factors
            exists =. 0
            for_previous. terms do.
                if. (t_keys item)-:t_keys >previous do.
                    exists =. 1
                    break.
                end.
            end.
            if. exists do.
                continue.
            end.
            terms =. terms,<item
            for_box. factors do.
                factor =. >box
                column =. f_column factor
                if. -.column e.factor_columns do.
                    factor_columns =. factor_columns,column
                    variables =. variables,column
                end.
                if. (f_categorical factor)*.-.column e.categorical_columns do.
                    categorical_columns =. categorical_columns,column
                end.
            end.
        end.
    end.
    response =. 0{::halves
    response_column =. x i.<response
    weight_column =. _1
    if. #weight do.
        weight_column =. x i.<weight
    end.
    variables =. variables,response_column
    if. weight_column>:0 do.
        variables =. variables,weight_column
    end.
    (<original),(<response),(<response_column),(<weight),(<weight_column),(<terms),(<factor_columns),(<categorical_columns),<variables
)
format_model =: 4 : 0
    names =. 0$a:
    for_index. y do.
        names =. names,<t_name index{::model_terms x
    end.
    if. #names do.
        result =. ''
        for_index. i.#names do.
            if. index do.
                result =. result,' + '
            end.
            result =. result,index{::names
        end.
    else.
        result =. '1'
    end.
    (model_response x),' ~ ',result
)
removable =: 4 : 0
    result =. i.0
    for_index. y do.
        allowed =. 1
        for_other. y do.
            if. (index{::x)contained other{::x do.
                allowed =. 0
                break.
            end.
        end.
        if. allowed do.
            result =. result,index
        end.
    end.
    result
)
candidates =: 4 : 0
    result =. i.0
    for_index. i.#x do.
        allowed =. -.index e.y
        for_other. i.#x do.
            if. ((other{::x)contained index{::x)*.-.other e.y do.
                allowed =. 0
            end.
        end.
        if. allowed do.
            result =. result,index
        end.
    end.
    result
)
hierarchical =: 4 : 0
    for_index. y do.
        for_other. i.#x do.
            if. ((other{::x)contained index{::x)*.-.other e.y do.
                0 return.
            end.
        end.
    end.
    1
)
component_value =: 4 : 0
    factor =. component_factor x
    value =. (f_column factor){::y
    if. f_categorical factor do.
        0.0+value-:component_level x return.
    end.
    number =. decimal value
    if. (f_power factor)=2 do.
        number*number
    elseif. (f_power factor)=3 do.
        (number*number)*number
    else.
        number
    end.
)
design_values =: 4 : 0
    result =. i.0
    for_box. x do.
        column =. >box
        components =. column_components column
        value =. 1.0
        for_index. i.#components do.
            next_value =. (index{::components)component_value y
            if. index=0 do.
                value =. next_value
            else.
                value =. value*next_value
            end.
        end.
        result =. result,value
    end.
    result
)
subset_matrix =: 3 : 0
    'matrix columns indices' =. y
    selected =. i.0
    for_column. i.#columns do.
        term =. column_term column{::columns
        if. (term<0)+.term e.indices do.
            selected =. selected,column
        end.
    end.
    selected{"1 matrix
)
predictable =: 3 : 0
    'model levels row' =. y
    for_column. model_factor_columns model do.
        value =. column{::row
        if. value-:'NA' do.
            0 return.
        end.
        known =. column{::levels
        if. (#known)*.-.(<value)e.known do.
            0 return.
        end.
    end.
    1
)
make_design =: 3 : 0
    'model data' =. y
    source =. df_rows data
    row_numbers =. i.0
    rows =. (0,#df_columns data)$a:
    for_index. i.#source do.
        row =. index{source
        if. *./-.((model_variables model){row)e.<'NA' do.
            rows =. rows,row
            row_numbers =. row_numbers,index+1
        end.
    end.
    levels =. 0$a:
    for_column. i.#df_columns data do.
        items =. 0$a:
        if. column e.model_categorical_columns model do.
            items =. /:~~.column{"1 rows
        end.
        levels =. levels,<items
    end.
    columns =. <(<_1),(<'(Intercept)'),<0$a:
    terms =. model_terms model
    for_term_index. i.#terms do.
        item =. term_index{::terms
        choices =. 0$a:
        total =. 1
        for_box. t_factors item do.
            factor =. >box
            components =. 0$a:
            if. f_categorical factor do.
                for_level. }.(f_column factor){::levels do.
                    components =. components,<(<factor),(<(f_name factor),>level),< >level
                end.
            else.
                components =. <(<factor),(<f_name factor),<''
            end.
            choices =. choices,<components
            total =. total*#components
        end.
        for_code. i.total do.
            remaining =. code
            names =. 0$a:
            components =. 0$a:
            for_box. choices do.
                options =. >box
                component =. ((#options)|remaining){::options
                remaining =. <.remaining%#options
                names =. names,<component_name component
                components =. components,<component
            end.
            name =. ''
            for_index. i.#names do.
                if. index do.
                    name =. name,':'
                end.
                name =. name,index{::names
            end.
            columns =. columns,<(<term_index),(<name),<components
        end.
    end.
    matrix =. (0,#columns)$0.0
    response =. i.0
    weights =. i.0
    for_row. rows do.
        matrix =. matrix,columns design_values row
        response =. response,decimal (model_response_column model){::row
        if. (model_weight_column model)>:0 do.
            weight =. decimal (model_weight_column model){::row
        else.
            weight =. 1.0
        end.
        weights =. weights,weight
    end.
    (<model),(<row_numbers),(<rows),(<levels),(<columns),(<matrix),(<response),<weights
)
