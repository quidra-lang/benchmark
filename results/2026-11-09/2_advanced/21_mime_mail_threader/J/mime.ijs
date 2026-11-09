hex_value =: 3 : 0
    index =. '0123456789abcdef'i.lower y
    if. index=16 do. _1 else. index end.
)
strict_base64 =: 3 : 0
    if. 0~:4|#y do. (<0),<'' return. end.
    content =. y
    while. #content do.
        if. '='~:{:content do. break. end.
        content =. }:content
    end.
    if. ((#y)-#content)>:3 do. (<0),<'' return. end.
    alphabet =. 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    buffer =. bits =. 0
    result =. ''
    for_character. content do.
        value =. alphabet i.character
        if. value=64 do. (<0),<'' return. end.
        buffer =. (buffer*64)+value
        bits =. bits+6
        if. bits>:8 do.
            bits =. bits-8
            result =. result,a.{~buffer div 2^bits
            buffer =. (2^bits)|buffer
        end.
    end.
    (<1),<result
)
base64_body =: 3 : 0
    'okay data' =. strict_base64 y#~-.y e.Whitespace,LF
    if. -.okay do. (<0),<'' return. end.
    result =. ''
    position =. 0
    while. position<#data do.
        code =. a.i.position{data
        if. (code=13)*.(position+1)<#data do.
            if. LF=(position+1){data do. code =. 10
                position =. position+1 end.
        end.
        if. (-.code e.9 10)*.((code<32)+.code>126) do. (<0),<'' return. end.
        result =. result,code{a.
        position =. position+1
    end.
    (<1),<result
)
quoted_printable =: 3 : 0
    lines =. LF split y
    result =. ''
    error =. 0
    for_index. i.#lines do.
        line =. strip_trailing index{::lines
        soft =. 0
        if. #line do. soft =. '='={:line end.
        if. soft do. line =. }:line end.
        position =. 0
        while. position<#line do.
            character =. position{line
            if. (character='=')*.(position+2)<#line do.
                first =. hex_value (position+1){line
                second =. hex_value (position+2){line
                value =. (16*first)+second
                if. (first>:0)*.(second>:0)*.((value=9)+.(value>:32)*.value<:126) do.
                    result =. result,value{a.
                    position =. position+3
                    continue.
                end.
            end.
            error =. error+.character='='
            result =. result,character
            position =. position+1
        end.
        if. (-.soft)*.index<(#lines)-1 do. result =. result,LF end.
    end.
    (<result),<error
)
