Keywords =: ;:'int bool void true false if else while for break continue return print read'
PairSymbols =: <;._1 ' <= >= == != && ||'
letter =: 3 : 'y e.''ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'''
digit =: 3 : 'y e.''0123456789'''
character_at =: 4 : 0
    if. (x>:0)*.x<#y do. x{y else. a.{~0 end.
)
lex_source =: 3 : 0
    source =. ''
    for_record. y do. source =. source,(1{::>record),LF end.
    row =. 0{::0{::y
    column =. 1
    position =. 0
    tokens =. 0$a:
    while. position<#source do.
        start =. position
        where =. row,column
        character =. position{source
        pair =. 2{.position}.source
        if. character=' ' do.
            position =. position+1
            column =. column+1
            continue.
        elseif. character=LF do.
            position =. position+1
            row =. row+1
            column =. 1
            continue.
        elseif. pair-:'//' do.
            skipped =. (position}.source)i.LF
            position =. position+skipped
            column =. column+skipped
            continue.
        elseif. pair-:'/*' do.
            found =. I.'*/' E.(position+2)}.source
            if. 0=#found do.
                compile_fail(<'lexical'),(<where),<'unterminated comment'
            end.
            position =. position+4+{.found
            consumed =. (position-start){.start}.source
            newlines =. I.consumed=LF
            if. #newlines do.
                row =. row+#newlines
                column =. (#consumed)-{:newlines
            else.
                column =. column+#consumed
            end.
            continue.
        end.
        position =. position+1
        if. (letter character)+.character='_' do.
            while. 1 do.
                current =. position character_at source
                if. -.(letter current)+.(digit current)+.current='_' do. break. end.
                position =. position+1
            end.
            spelling =. (position-start){.start}.source
            kind =. 'identifier'
            if. (<spelling)e.Keywords do. kind =. 'keyword' end.
        elseif. digit character do.
            while. digit position character_at source do. position =. position+1 end.
            spelling =. (position-start){.start}.source
            if. (".spelling,'x')>2147483647x do.
                compile_fail(<'lexical'),(<where),<'integer literal too large'
            end.
            kind =. 'integer'
        elseif. (<pair)e.PairSymbols do.
            position =. position+1
            spelling =. pair
            kind =. 'symbol'
        elseif. character e.'+-*/%<>=!(){}[],;' do.
            spelling =. ,character
            kind =. 'symbol'
        else.
            quote =. 39{a.
            compile_fail(<'lexical'),(<where),<'unexpected character ',quote,character,quote
        end.
        tokens =. tokens,<(<kind),(<spelling),<where
        column =. column+position-start
    end.
    'last_line last_text' =. _1{::y
    tokens,<(<'end'),(<''),<last_line,1+#last_text
)
