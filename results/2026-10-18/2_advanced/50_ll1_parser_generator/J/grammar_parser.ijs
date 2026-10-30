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
number_text =: 3 : '":y'
is_nt =: 3 : 0
    ('<'={.y)*.'>'={:y
)
alt_text =: 3 : 0
    if. #y do.
        ' 'join y
    else.
        '%empty'
    end.
)
production_text =: 4 : 'x,'' -> '',alt_text y'
is_letter =: 3 : 'y e.''ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'''
is_word_character =: 3 : 'y e.''ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_'''
lex_line =: 3 : 0
    line =. y
    tokens =. 0$a:
    cursor =. 0
    while. cursor<#line do.
        character =. cursor{line
        if. character=' ' do.
            cursor =. cursor+1
            continue.
        elseif. character='#' do.
            break.
        end.
        start =. cursor
        kind =. 'invalid'
        value =. ,character
        if. character='<' do.
            finish =. cursor+1
            valid =. finish<#line
            if. valid do.
                valid =. is_letter finish{line
            end.
            if. valid do.
                finish =. finish+1
                while. finish<#line do.
                    if. -.is_word_character finish{line do.
                        break.
                    end.
                    finish =. finish+1
                end.
                if. finish<#line do.
                    if. '>'=finish{line do.
                        kind =. 'nonterminal'
                        cursor =. finish+1
                        value =. (cursor-start){.start}.line
                    end.
                end.
            end.
        elseif. character='"' do.
            finish =. cursor+1
            while. finish<#line do.
                if. (finish{line)e.' "' do.
                    break.
                end.
                finish =. finish+1
            end.
            if. (finish>cursor+1)*.finish<#line do.
                if. '"'=finish{line do.
                    kind =. 'terminal'
                    value =. (finish-(cursor+1)){.(cursor+1)}.line
                    cursor =. finish+1
                end.
            end.
        elseif. is_letter character do.
            cursor =. cursor+1
            while. cursor<#line do.
                if. -.is_word_character cursor{line do.
                    break.
                end.
                cursor =. cursor+1
            end.
            kind =. 'word'
            value =. (cursor-start){.start}.line
        elseif. '::='-:3{.cursor}.line do.
            kind =. 'definition'
            value =. '::='
            cursor =. cursor+3
        elseif. character='|' do.
            kind =. 'separator'
            cursor =. cursor+1
        elseif. character='%' do.
            finish =. cursor+1
            while. finish<#line do.
                if. -.is_letter finish{line do.
                    break.
                end.
                finish =. finish+1
            end.
            name =. (finish-(cursor+1)){.(cursor+1)}.line
            if. (<name)e.;:'empty start token' do.
                kind =. 'directive'
                value =. '%',name
                cursor =. finish
            end.
        end.
        if. kind-:'invalid' do.
            cursor =. start+1
        end.
        tokens =. tokens,<(<kind),(<value),(<start+1),<cursor
        if. kind-:'invalid' do.
            break.
        end.
    end.
    tokens
)
error_column =: 4 : 0
    if. x<#y do.
        2{::x{::y
    else.
        1+3{::>{:y
    end.
)
alternative_list =: 4 : 0
    cursor =. x
    tokens =. y
    result =. 0$a:
    while. 1 do.
        if. cursor>:#tokens do.
            (<0$a:),<cursor error_column tokens return.
        end.
        token =. cursor{::tokens
        rhs =. 0$a:
        if. ('directive'-:0{::token)*.'%empty'-:1{::token do.
            cursor =. cursor+1
        elseif. (0{token)e.;:'nonterminal terminal word' do.
            while. cursor<#tokens do.
                token =. cursor{::tokens
                if. -. (0{token)e.;:'nonterminal terminal word' do.
                    break.
                end.
                rhs =. rhs,1{token
                cursor =. cursor+1
            end.
        else.
            (<0$a:),<cursor error_column tokens return.
        end.
        result =. result,<rhs
        if. cursor=#tokens do.
            (<result),<0 return.
        end.
        if. -. 'separator'-:0{::cursor{::tokens do.
            (<0$a:),<cursor error_column tokens return.
        end.
        cursor =. cursor+1
    end.
)
invalid_line =: 3 : '(<''invalid''),(<''''),(<0$a:),(<0$a:),<y'
parse_line =: 3 : 0
    tokens =. y
    if. 0=#tokens do.
        (<'blank'),(<''),(<0$a:),(<0$a:),<0 return.
    end.
    first =. 0{::tokens
    kind =. 0{::first
    value =. 1{::first
    if. kind-:'nonterminal' do.
        if. 2>#tokens do.
            invalid_line 1 error_column tokens return.
        end.
        if. -. 'definition'-:0{::1{::tokens do.
            invalid_line 1 error_column tokens return.
        end.
        'alternatives column' =. 2 alternative_list tokens
        if. column do.
            invalid_line column return.
        end.
        (<'rule'),(<value),(<alternatives),(<0$a:),<0
    elseif. kind-:'separator' do.
        'alternatives column' =. 1 alternative_list tokens
        if. column do.
            invalid_line column return.
        end.
        (<'continuation'),(<''),(<alternatives),(<0$a:),<0
    elseif. (kind-:'directive')*.value-:'%start' do.
        if. 2>#tokens do.
            invalid_line 1 error_column tokens return.
        end.
        if. -. 'nonterminal'-:0{::1{::tokens do.
            invalid_line 1 error_column tokens return.
        end.
        if. 2<#tokens do.
            invalid_line 2 error_column tokens return.
        end.
        (<'start'),(1{1{::tokens),(<0$a:),(<0$a:),<0
    elseif. (kind-:'directive')*.value-:'%token' do.
        if. 2>#tokens do.
            invalid_line 1 error_column tokens return.
        end.
        words =. 0$a:
        for_i. }.i.#tokens do.
            token =. i{::tokens
            if. -. 'word'-:0{::token do.
                invalid_line i error_column tokens return.
            end.
            words =. words,1{token
        end.
        (<'declaration'),(<''),(<0$a:),(<words),<0
    else.
        invalid_line 2{::first
    end.
)
parse_grammar =: 3 : 0
    order =. 0$a:
    rules =. 0$a:
    start =. ''
    diagnostics =. 0$a:
    declared =. 0$a:
    has_declarations =. 0
    word_names =. 0$a:
    word_lines =. i.0
    attached =. _1
    for_number. i.#y do.
        tokens =. lex_line number{::y
        'kind lhs alternatives words column' =. parse_line tokens
        if. kind-:'blank' do.
            continue.
        elseif. kind-:'invalid' do.
            diagnostics =. diagnostics,<'line ',(number_text number+1),': syntax error at column ',number_text column
            attached =. _1
        elseif. kind-:'start' do.
            if. #start do.
                diagnostics =. diagnostics,<'line ',(number_text number+1),': duplicate %start'
            else.
                start =. lhs
            end.
            attached =. _1
        elseif. kind-:'declaration' do.
            declared =. ~.declared,words
            has_declarations =. 1
            attached =. _1
        else.
            if. kind-:'rule' do.
                attached =. order i.<lhs
                if. attached=#order do.
                    order =. order,<lhs
                    rules =. rules,<0$a:
                end.
            elseif. attached<0 do.
                diagnostics =. diagnostics,<'line ',(number_text number+1),': continuation without a rule'
            end.
            if. attached>:0 do.
                for_box. tokens do.
                    token =. >box
                    if. 'word'-:0{::token do.
                        name =. 1{token
                        if. -.name e.word_names do.
                            word_names =. word_names,name
                            word_lines =. word_lines,number+1
                        end.
                    end.
                end.
                held =. attached{::rules
                for_box. alternatives do.
                    rhs =. >box
                    if. (<rhs)e.held do.
                        diagnostics =. diagnostics,<'line ',(number_text number+1),': duplicate alternative ',(attached{::order)production_text rhs
                    else.
                        held =. held,<rhs
                    end.
                end.
                rules =. (<held)attached}rules
            end.
        end.
    end.
    if. 0=#start do.
        start =. 0{::order
    end.
    model =. (<order),(<rules),<start
    (<model),(<diagnostics),(<declared),(<has_declarations),(<word_names),<word_lines
)
