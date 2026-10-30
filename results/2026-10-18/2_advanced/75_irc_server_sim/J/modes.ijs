channel_items =: 4 : 0
    mode =. x
    arguments =. y
    items =. 0$a:
    sign =. '+'
    position =. 0
    for_character. mode do.
        if. character e.'+-' do.
            sign =. character
            continue.
        end.
        argument =. ''
        has_argument =. 0
        if. (character e.'ovbk')+.((character='l')*.sign='+') do.
            if. position<#arguments do.
                argument =. position{::arguments
                position =. position+1
                has_argument =. 1
            end.
        end.
        if. (character='k')*.sign='-' do.
            argument =. '*'
            has_argument =. 1
        elseif. (character='l')*.sign='+' do.
            valid =. 0
            if. has_argument do.
                if. (digits argument)*.(#argument)<:4 do.
                    valid =. 0<".argument
                end.
            end.
            has_argument =. valid
        end.
        items =. items,<sign;character;argument;has_argument
    end.
    items
)
change_string =: 3 : 0
    mode =. ''
    arguments =. 0$a:
    previous =. ''
    for_change. y do.
        'sign character argument has_argument' =. >change
        if. -.sign-:previous do.
            mode =. mode,sign
            previous =. sign
        end.
        mode =. mode,character
        if. has_argument do.
            arguments =. arguments,<argument
        end.
    end.
    for_argument. arguments do.
        mode =. mode,' ',>argument
    end.
    mode
)
