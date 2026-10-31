Keywords =: ;:'let rec and in fun if then else match with true false mod val'
DoubleSymbols =: <;._1 ' ;; -> :: || && <= >= <>'
letter =: 3 : 'y e.''ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'''
word_character =: 3 : '(letter y)+.y e.''0123456789_'''
digit =: 3 : 'y e.''0123456789'''
character_at =: 4 : 0
    if. (x>:0)*.x<#y do. x{y else. a.{~0 end.
)
lex_source =: 4 : 0
    file =. x
    source =. y
    tokens =. 0$a:
    index =. 0
    row =. column =. 1
    while. index<#source do.
        start =. index
        position =. file,row,column
        character =. index{source
        pair =. 2{.index}.source
        kind =. ''
        value =. ''
        if. character e.' ',LF do.
            index =. index+1
        elseif. pair-:'(*' do.
            found =. I.'*)' E.(index+2)}.source
            if. 0=#found do.
                kind =. 'invalid'
                value =. 'unterminated comment'
                index =. #source
            else.
                index =. index+4+{.found
            end.
        elseif. digit character do.
            index =. index+1
            while. digit index character_at source do. index =. index+1 end.
            text =. (index-start){.start}.source
            number =. ".text,'x'
            kind =. 'integer'
            value =. number
            if. number>2147483647x do.
                kind =. 'invalid'
                value =. 'integer literal too large'
            end.
        elseif. (letter character)+.character='_' do.
            index =. index+1
            while. (word_character index character_at source)+.(39{a.)=index character_at source do.
                index =. index+1
            end.
            value =. (index-start){.start}.source
            kind =. 'identifier'
            if. (<value)e.Keywords do. kind =. value end.
        elseif. (character=39{a.)*.((index+1)character_at source)e.'abcdefghijklmnopqrstuvwxyz' do.
            index =. index+2
            while. word_character index character_at source do. index =. index+1 end.
            value =. (index-start){.start}.source
            kind =. 'type_variable'
        elseif. character='"' do.
            index =. index+1
            invalid =. 0
            decoded =. ''
            while. index<#source do.
                current =. index{source
                if. current e.'"',LF do. break. end.
                if. (current='\')*.LF~:(index+1)character_at source do.
                    escape =. (index+1)character_at source
                    select. escape
                    case. 'n' do. decoded =. decoded,LF
                    case. 't' do. decoded =. decoded,9{a.
                    case. '\';'"' do. decoded =. decoded,escape
                    case. do. invalid =. 1
                    end.
                    index =. index+2
                else.
                    decoded =. decoded,current
                    index =. index+1
                end.
            end.
            if. '"'~:index character_at source do.
                kind =. 'invalid'
                value =. 'unterminated string'
            else.
                index =. index+1
                if. invalid do.
                    kind =. 'invalid'
                    value =. 'invalid escape sequence'
                else.
                    kind =. 'string'
                    value =. decoded
                end.
            end.
        elseif. (<pair)e.DoubleSymbols do.
            kind =. value =. pair
            index =. index+2
        elseif. character e.':;=<>+-*/^()[],|' do.
            kind =. value =. ,character
            index =. index+1
        else.
            kind =. 'invalid'
            quote =. 39{a.
            value =. 'illegal character ',quote,character,quote
            index =. index+1
        end.
        consumed =. (index-start){.start}.source
        if. #kind do.
            tokens =. tokens,<(<kind),(<consumed),(<value),<position
        end.
        newlines =. I.consumed=LF
        if. #newlines do.
            row =. row+#newlines
            column =. (#consumed)-{:newlines
        else.
            column =. column+#consumed
        end.
    end.
    position =. file,(1++/source=LF),1
    tokens,< (<'EOF'),(<''),(<''),<position
)
