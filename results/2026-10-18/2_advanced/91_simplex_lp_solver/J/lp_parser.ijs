split_words =: 3 : '<;._1 '' '',y'
is_name =: 3 : 0
    if. 0=#y do. 0 return. end.
    if. -.({.y)e.'abcdefghijklmnopqrstuvwxyz' do. 0 return. end.
    if. -.*./y e.'abcdefghijklmnopqrstuvwxyz0123456789_' do. 0 return. end.
    -.(<y)e.;:'bounds integer binary free inf'
)
parse_expression =: 3 : 0
    terms =. 0$a:
    position =. 0
    sign =. 1x
    if. #y do.
        if. (0{::y)-:,'-' do.
            sign =. _1x
            position =. 1
        end.
    end.
    while. position<#y do.
        text =. position{::y
        value =. 0 read_number text
        if. finite value do.
            if. (position+1)=#y do. 0$a: return. end.
            name =. (position+1){::y
            if. -.is_name name do. 0$a: return. end.
            position =. position+2
        elseif. is_name text do.
            value =. 1x
            name =. text
            position =. position+1
        else.
            0$a: return.
        end.
        terms =. terms,<(<name),<sign*value
        if. position=#y do. terms return. end.
        operator =. position{::y
        if. -.(<operator)e.(<,'+'),<,'-' do. 0$a: return. end.
        sign =. 1x
        if. operator-:,'-' do. sign =. _1x end.
        position =. position+1
    end.
    0$a:
)
named_expression =: 3 : 0
    if. (#y)<2 do. 0$a: return. end.
    first =. 0{::y
    if. ':'~:{:first do. 0$a: return. end.
    name =. }:first
    if. -.is_name name do. 0$a: return. end.
    terms =. parse_expression }.y
    if. 0=#terms do. 0$a: else. (<name),<terms end.
)
parse_constraint =: 4 : 0
    if. (#y)<4 do. 0$a: return. end.
    comparison =. _2{::y
    if. -.(<comparison)e.('<=';'>='),<,'=' do. 0$a: return. end.
    rhs =. 1 read_number _1{::y
    named =. named_expression _2}.y
    if. (-.finite rhs)+.0=#named do. 0$a: return. end.
    'name terms' =. named
    (<x),(<name),(<terms),(<comparison),<rhs
)
parse_bound =: 4 : 0
    if. 2=#y do.
        'name value' =. y
        if. (is_name name)*.value-:'free' do.
            (<x),(<name),(<'both'),(<''),<'' return.
        end.
    elseif. 3=#y do.
        'name operator text' =. y
        if. -.is_name name do. 0$a: return. end.
        value =. 1 read_number text
        if. (operator-:'>=')*.((finite value)+.text-:'-inf') do.
            (<x),(<name),(<'lower'),(<value),<'' return.
        elseif. (operator-:'<=')*.((finite value)+.text-:'inf') do.
            (<x),(<name),(<'upper'),(<''),<value return.
        elseif. (operator-:,'=')*.finite value do.
            (<x),(<name),(<'both'),(<value),<value return.
        end.
    elseif. 5=#y do.
        'low first name second high' =. y
        if. (first-:'<=')*.(second-:'<=')*.is_name name do.
            lower =. 1 read_number low
            upper =. 1 read_number high
            if. ((finite lower)+.low-:'-inf')*.((finite upper)+.high-:'inf') do.
                (<x),(<name),(<'both'),(<lower),<upper return.
            end.
        end.
    end.
    0$a:
)
parse_block =: 3 : 0
    'name body end_line' =. y
    error =. 0$a:
    direction =. ''
    objective =. constraints =. bounds =. integers =. binaries =. 0$a:
    state =. 0
    for_record. body do.
        'line text' =. >record
        words =. split_words text
        accepted =. 0
        select. state
        case. 0 do.
            if. (<text)e.'maximize';'minimize' do.
                direction =. text
                state =. 1
                accepted =. 1
            end.
        case. 1 do.
            named =. named_expression words
            if. #named do.
                objective =. 1{::named
                state =. 2
                accepted =. 1
            end.
        case. 2 do.
            if. text-:'subject to' do.
                state =. 3
                accepted =. 1
            end.
        case. 3;4 do.
            if. (state=4)*.(<text)e.;:'bounds integer binary' do.
                state =. 5+(;:'bounds integer binary')i.<text
                accepted =. 1
            else.
                item =. line parse_constraint words
                if. #item do.
                    constraints =. constraints,<item
                    state =. 4
                    accepted =. 1
                end.
            end.
        case. 5 do.
            if. (<text)e.'integer';'binary' do.
                state =. 6+text-:'binary'
                accepted =. 1
            else.
                item =. line parse_bound words
                if. #item do.
                    bounds =. bounds,<item
                    accepted =. 1
                end.
            end.
        case. 6;7 do.
            if. (state=6)*.text-:'binary' do.
                state =. 7
                accepted =. 1
            elseif. *./is_name&>words do.
                item =. (<line),<words
                if. state=6 do. integers =. integers,<item else. binaries =. binaries,<item end.
                accepted =. 1
            end.
        end.
        if. -.accepted do.
            error =. (<line),<'syntax error'
            break.
        end.
    end.
    if. (0=#error)*.state<4 do. error =. (<end_line),<'syntax error' end.
    (<name),(<error),(<direction),(<objective),(<constraints),(<bounds),(<integers),<binaries
)
read_models =: 3 : 0
    models =. 0$a:
    name =. ''
    body =. 0$a:
    lines =. <;._2(1!:1 <'input/models.lp')
    for_i. i.#lines do.
        text =. i{::lines
        if. 0=#text do. continue. end.
        if. '#'={.text do. continue. end.
        if. 0=#name do.
            name =. 1{::split_words text
            body =. 0$a:
        elseif. text-:'end' do.
            models =. models,<parse_block(<name),(<body),<i+1
            name =. ''
        else.
            body =. body,<(<i+1),<text
        end.
    end.
    models
)
read_settings =: 3 : 0
    lines =. <;._2(1!:1 <'input/params.txt')
    DefaultLevel =: ".1{::split_words 0{::lines
    DefaultLimit =: ".1{::split_words 1{::lines
    LogNames =: LimitNames =: 0$a:
    LogValues =: LimitValues =: i.0
    for_line. 2}.lines do.
        'kind name text' =. split_words >line
        if. kind-:'log' do.
            LogNames =: LogNames,<name
            LogValues =: LogValues,".text
        else.
            LimitNames =: LimitNames,<name
            LimitValues =: LimitValues,".text
        end.
    end.
)
