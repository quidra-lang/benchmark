parse_fields =: 3 : 0
    names =. values =. 0$a:
    invalid =. 0$0
    infield =. 0
    for_line. y do.
        'line_number line' =. >line
        if. (#line)*.({.line)e.Whitespace do.
            if. infield do. values =. (<(>{:values),line)(<:#values)}values
            else. invalid =. invalid,line_number end.
            continue.
        end.
        colon =. line i.':'
        name =. colon{.line
        codes =. a.i.name
        infield =. (colon<#line)*.(colon>0)*.*./(codes>:33)*.codes<:126
        if. infield do.
            names =. names,<lower name
            values =. values,<(colon+1)}.line
        else. invalid =. invalid,line_number end.
    end.
    values =. strip&.>values
    (<names),(<values),<invalid
)
header_has =: 4 : '(<lower y)e.0{::x'
header_value =: 4 : 0
    'names values invalid' =. x
    position =. names i.<lower y
    if. position<#names do. position{::values else. '' end.
)
header_count =: 4 : '+/(<lower y)=0{::x'
remove_comments =: 3 : 0
    result =. ''
    depth =. 0
    position =. 0
    while. position<#y do.
        character =. position{y
        if. depth=0 do.
            if. character='(' do. depth =. 1
                result =. result,' '
            else. result =. result,character end.
        elseif. character='\' do. position =. position+1
        elseif. character='(' do. depth =. depth+1
        elseif. character=')' do. depth =. depth-1 end.
        position =. position+1
    end.
    (<depth=0),<result
)
tokenize =: 4 : 0
    if. x do.
        specials =. '/;='
        wordchars =. (33+i.94){a.
        wordchars =. wordchars#~-.wordchars e.'()<>@,;:\"/[]?='
    else.
        specials =. '<>:;@,.'
        wordchars =. Letters,Digits,'!#$%&''*+-/=?^_`{|}~'
    end.
    tokens =. 0$a:
    TokensOkay =: 1
    spaced =. 0
    position =. 0
    while. position<#y do.
        character =. position{y
        if. character e.Whitespace do. spaced =. 1
            position =. position+1
            continue.
        elseif. character='(' do.
            depth =. 1
            position =. position+1
            while. (position<#y)*.depth>0 do.
                character =. position{y
                position =. position+1
                if. character='\' do. position =. position+1
                elseif. character='(' do. depth =. depth+1
                elseif. character=')' do. depth =. depth-1 end.
            end.
            if. depth do. TokensOkay =: 0 return. end.
            spaced =. 1
            continue.
        elseif. character='"' do.
            value =. ''
            closed =. 0
            position =. position+1
            while. position<#y do.
                character =. position{y
                position =. position+1
                if. character='"' do. closed =. 1 break. end.
                if. character='\' do.
                    if. position=#y do. break. end.
                    character =. position{y
                    position =. position+1
                end.
                value =. value,character
            end.
            if. -.closed do. TokensOkay =: 0 return. end.
            kind =. 'quoted'
        elseif. character e.specials do.
            kind =. value =. ,character
            position =. position+1
        elseif. character e.wordchars do.
            start =. position
            while. position<#y do.
                if. -. (position{y)e.wordchars do. break. end.
                position =. position+1
            end.
            kind =. 'word'
            value =. (position-start){.start}.y
        else. TokensOkay =: 0 return. end.
        tokens =. tokens,<(<kind),(<value),<spaced
        spaced =. 0
    end.
    tokens
)
decode_word =: 3 : 0
    original =. (<y),(<0),<0
    if. (#y)<4 do. original return. end.
    if. (-.'=?'-:2{.y)+.-.'?='-:_2{.y do. original return. end.
    pieces =. '?' split _2}.2}.y
    if. (#pieces)~:3 do. original return. end.
    if. 0 e.#&>pieces do. original return. end.
    'charset encoding encoded' =. pieces
    failed =. (<y),(<0),<1
    if. -.'us-ascii'-:lower charset do. failed return. end.
    if. (<encoding)e.'B';'b' do.
        'okay result' =. strict_base64 encoded
        if. -.okay do. failed return. end.
    elseif. (<encoding)e.'Q';'q' do.
        result =. ''
        position =. 0
        while. position<#encoded do.
            character =. position{encoded
            if. character='_' do. result =. result,' '
                position =. position+1
            elseif. character='=' do.
                if. (position+2)>:#encoded do. failed return. end.
                first =. hex_value (position+1){encoded
                second =. hex_value (position+2){encoded
                if. (first<0)+.second<0 do. failed return. end.
                result =. result,a.{~(16*first)+second
                position =. position+3
            else. result =. result,character
                position =. position+1 end.
        end.
    else. failed return. end.
    codes =. a.i.result
    if. -. *./(codes>:32)*.codes<:126 do. failed return. end.
    (<result),(<1),<0
)
decode_unstructured =: 3 : 0
    result =. ''
    first =. 1
    previous =. error =. 0
    for_word. words y do.
        'value decoded failed' =. decode_word >word
        if. (-.first)*.-.previous*.decoded do. result =. result,' ' end.
        result =. result,value
        previous =. decoded
        error =. error+.failed
        first =. 0
    end.
    (<collapse result),<error
)
parse_parameters =: 4 : 0
    failed =. (<0),(<''),(<''),(<0$a:),<0$a:
    tokens =. 1 tokenize y
    if. (-.TokensOkay)+.0=#tokens do. failed return. end.
    if. -.'word'-:0{::0{::tokens do. failed return. end.
    main =. lower 1{::0{::tokens
    subtype =. ''
    position =. 1
    if. x do.
        if. (#tokens)<3 do. failed return. end.
        if. (-.'/'-:0{::1{::tokens)+.-.'word'-:0{::2{::tokens do. failed return. end.
        subtype =. lower 1{::2{::tokens
        position =. 3
    end.
    names =. values =. 0$a:
    while. position<#tokens do.
        if. (position+3)>:#tokens do. failed return. end.
        group =. (position+i.4){tokens
        kinds =. 0$a:
        for_token. group do. kinds =. kinds,0{>token end.
        if. (-.(3{.kinds)-:(';';'word';'='))+.-.(3{kinds)e.'word';'quoted' do. failed return. end.
        name =. lower 1{::1{::group
        if. -.(<name)e.names do.
            names =. names,<name
            values =. values,<1{::3{::group
        end.
        position =. position+4
    end.
    (<1),(<main),(<subtype),(<names),<values
)
