Keywords =: ;:'int float bool string void if else while for return break continue true false switch case default'
TypeNames =: ;:'int float bool string void'
DoubleSymbols =: <;._1 ' <= >= == != && || += -= *= /= %='
AssignmentSymbols =: <;._1 ' = += -= *= /= %='
letter =: 3 : 'y e.''ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_'''
digit =: 3 : 'y e.''0123456789'''
character_at =: 4 : 0
    if. (x>:0)*.x<#y do. x{y else. a.{~0 end.
)
lex_source =: 3 : 0
    Tokens =: Comments =: LexicalItems =: 0$a:
    error =. 0$a:
    previous =. 0
    for_row. i.#y do.
        line =. row{::y
        position =. 0
        while. position<#line do.
            character =. position{line
            if. character=' ' do.
                position =. position+1
                continue.
            end.
            start =. position
            pair =. 2{.position}.line
            if. pair-:'//' do.
                kind =. 'line_comment'
                position =. #line
                text =. trim_spaces start}.line
            elseif. pair-:'/*' do.
                rest =. (position+2)}.line
                found =. I.'*/' E.rest
                if. 0=#found do.
                    error =. (<row+1),(<start+1),<'unterminated comment'
                    break.
                end.
                position =. position+4+{.found
                kind =. 'block_comment'
                text =. (position-start){.start}.line
            elseif. letter character do.
                position =. position+1
                while. (letter position character_at line)+.digit position character_at line do.
                    position =. position+1
                end.
                text =. (position-start){.start}.line
                kind =. 'identifier'
                if. (<text)e.Keywords do. kind =. 'keyword' end.
            elseif. digit character do.
                position =. position+1
                while. digit position character_at line do. position =. position+1 end.
                if. ('.'=position character_at line)*.digit(position+1)character_at line do.
                    position =. position+2
                    while. digit position character_at line do. position =. position+1 end.
                end.
                text =. (position-start){.start}.line
                kind =. 'number'
            elseif. character='"' do.
                position =. position+1
                closed =. 0
                while. position<#line do.
                    if. '\'=position{line do.
                        position =. position+2
                    elseif. '"'=position{line do.
                        position =. position+1
                        closed =. 1
                        break.
                    else.
                        position =. position+1
                    end.
                end.
                if. -.closed do.
                    error =. (<row+1),(<start+1),<'unterminated string'
                    break.
                end.
                text =. (position-start){.start}.line
                kind =. 'string'
            elseif. (<pair)e.DoubleSymbols do.
                text =. pair
                kind =. 'symbol'
                position =. position+2
            elseif. character e.'+-*/%<>=!()[]{},;.?:' do.
                text =. ,character
                kind =. 'symbol'
                position =. position+1
            else.
                apostrophe =. 39{a.
                message =. 'unexpected character ',apostrophe,character,apostrophe
                error =. (<row+1),(<start+1),<message
                break.
            end.
            blank =. 0>.row-previous
            previous =. row+1
            entry =. (<kind),(<text),(<row+1),(<start+1),<blank
            if. (<kind)e.'line_comment';'block_comment' do.
                LexicalItems =: LexicalItems,<1,#Comments
                Comments =: Comments,<entry,<0
            else.
                LexicalItems =: LexicalItems,<0,#Tokens
                entry =. entry,(<i.0),(<i.0),(<0),<0
                Tokens =: Tokens,<entry
            end.
        end.
        if. #error do. break. end.
    end.
    entry =. (<'end'),(<''),(<1+#y),(<1),(<0),(<i.0),(<i.0),(<1),<0
    Tokens =: Tokens,<entry
    error
)
