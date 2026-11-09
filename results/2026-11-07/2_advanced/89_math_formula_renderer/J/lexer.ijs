initialize_lexicon =: 3 : 0
    GreekNames =: ;:'alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi pi rho sigma tau'
    GreekNames =: GreekNames,;:'upsilon phi chi psi omega Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega'
    FunctionNames =: ;:'sin cos tan log ln exp det lim max min'
    LargeNames =: ;:'sum prod int'
    Accents =: ;:'overline hat vec dot tilde overbrace underbrace'
    Constructs =: ;:'frac binom overset underset sqrt left right'
    RawCommands =: ;:'text begin end tag label eqref'
    Environments =: ;:'matrix pmatrix bmatrix vmatrix cases'
    CommandNames =: GreekNames,FunctionNames,LargeNames
    CommandKeys =: 0$a:
    CommandDisplays =: 0$a:
    CommandTypes =: i.0
    for_name. CommandNames do.
        name =. >name
        CommandKeys =: CommandKeys,<('\',name)
        CommandDisplays =: CommandDisplays,<name
        type =. 0
        if. (<name)e.FunctionNames,LargeNames do.
            type =. 1
        end.
        CommandTypes =: CommandTypes,type
    end.
    names =. ;:'cdot times pm mp leq geq neq approx to infty ldots cdots quad'
    displays =. ('*';'x';'+-';'-+';'<=';'>=';'!=';'~=';'->';'oo';'...';'...'),<'  '
    types =. 2 2 2 2 3 3 3 3 3 0 0 0 0
    for_i. i.#names do.
        name =. i{::names
        CommandNames =: CommandNames,<name
        CommandKeys =: CommandKeys,<('\',name)
        CommandDisplays =: CommandDisplays,<,i{::displays
        CommandTypes =: CommandTypes,i{types
    end.
    CommandKeys =: CommandKeys,'\,';'\{';'\}'
    CommandDisplays =: CommandDisplays,(<,' '),(<,'{'),<,'}'
    CommandTypes =: CommandTypes,0 4 5
)
letter =: 3 : 'y e.''ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'''
digit =: 3 : 'y e.''0123456789'''
character_at =: 4 : 0
    if. (x>:0)*.x<#y do.
        x{y
    else.
        a.{~0
    end.
)
lex_formula =: 3 : 0
    line =. y
    tokens =. 0$a:
    position =. 0
    error =. 0$a:
    while. position<#line do.
        character =. position{line
        column =. position+1
        if. character=' ' do.
            position =. position+1
            continue.
        end.
        if. letter character do.
            end =. position+1
            while. letter end character_at line do.
                end =. end+1
            end.
            kind =. 'identifier'
            value =. (end-position){.position}.line
            position =. end
        elseif. digit character do.
            end =. position+1
            while. digit end character_at line do.
                end =. end+1
            end.
            if. ('.'=end character_at line)*.digit (end+1)character_at line do.
                end =. end+2
                while. digit end character_at line do.
                    end =. end+1
                end.
            end.
            kind =. 'number'
            value =. (end-position){.position}.line
            position =. end
        elseif. character e.'+-*/=<>:()[],;.!|''{}^_&' do.
            kind =. 'symbol'
            if. character e.'{}^_&' do.
                kind =. character
            end.
            value =. ,character
            position =. position+1
        elseif. character='\' do.
            position =. position+1
            escaped =. position character_at line
            if. escaped e.'\{},' do.
                kind =. 'command'
                if. escaped='\' do.
                    kind =. 'newline'
                end.
                value =. '\',escaped
                position =. position+1
            else.
                start =. position
                while. letter position character_at line do.
                    position =. position+1
                end.
                name =. (position-start){.start}.line
                if. 0=#name do.
                    error =. (<column),<'invalid command'
                    break.
                end.
                if. (<name)e.RawCommands do.
                    while. ' '=position character_at line do.
                        position =. position+1
                    end.
                    if. '{'~:position character_at line do.
                        error =. (<position+1),<'expected {'
                        break.
                    end.
                    rest =. (position+1)}.line
                    offset =. rest i.'}'
                    if. offset=#rest do.
                        error =. (<column),<'unterminated argument'
                        break.
                    end.
                    value =. offset{.rest
                    if. (<name)e.'begin';'end' do.
                        if. -.(<value)e.Environments do.
                            error =. (<column),<'unknown environment "',value,'"'
                            break.
                        end.
                    end.
                    kind =. name
                    position =. position+offset+2
                elseif. (<name)e.CommandNames do.
                    kind =. 'command'
                    value =. '\',name
                elseif. (<name)e.Accents do.
                    kind =. 'accent'
                    value =. name
                elseif. (<name)e.Constructs do.
                    kind =. name
                    value =. name
                else.
                    error =. (<column),<'unknown command \',name
                    break.
                end.
            end.
        else.
            error =. (<column),<'invalid character ',character
            break.
        end.
        tokens =. tokens,<( <kind),(<value),<column
    end.
    if. 0=#error do.
        tokens =. tokens,<( <'eof'),(<''),<1+#line
    end.
    (<tokens),<error
)
