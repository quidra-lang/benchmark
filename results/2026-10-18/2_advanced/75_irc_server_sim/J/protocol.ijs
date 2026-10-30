Letters =: 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
Special =: '[]\`_^{}|'
FoldTable =: 'abcdefghijklmnopqrstuvwxyz{}|~'(a.i.'ABCDEFGHIJKLMNOPQRSTUVWXYZ[]\^')}a.
UpperTable =: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'(a.i.'abcdefghijklmnopqrstuvwxyz')}a.
fold =: 3 : 'FoldTable{~a.i.y'
upper =: 3 : 'UpperTable{~a.i.y'
intdiv =: 4 : '<.(x:x)%x:y'
digits =: 3 : '(0<#y)*.*./y e.''0123456789'''
valid_nickname =: 3 : 0
    if. 0=#y do.
        0 return.
    end.
    (({.y)e.Letters,Special)*.*./(}.y)e.Letters,Special,'0123456789-'
)
valid_channel =: 4 : 0
    (2<:#y)*.((#y)<:x)*.('#'={.y)*.-.':'e.y
)
split_first =: 3 : 0
    at =. y i.' '
    (at{.y);(>:at)}.y
)
split_commas =: 3 : '<;._1 '','',y'
parse_message =: 3 : 0
    raw =. y
    length =. #raw
    position =. 0
    if. ':'={.raw do.
        position =. raw i.' '
        if. position=length do.
            (<''),(<0$a:) return.
        end.
    end.
    while. position<length do.
        if. ' '~:position{raw do.
            break.
        end.
        position =. position+1
    end.
    start =. position
    while. position<length do.
        if. ' '=position{raw do.
            break.
        end.
        position =. position+1
    end.
    command =. upper (position-start){.start}.raw
    parameters =. 0$a:
    while. position<length do.
        while. position<length do.
            if. ' '~:position{raw do.
                break.
            end.
            position =. position+1
        end.
        if. position=length do.
            break.
        end.
        if. ':'=position{raw do.
            parameters =. parameters,< (position+1)}.raw
            break.
        end.
        if. 14=#parameters do.
            parameters =. parameters,<position}.raw
            break.
        end.
        start =. position
        while. position<length do.
            if. ' '=position{raw do.
                break.
            end.
            position =. position+1
        end.
        parameters =. parameters,<(position-start){.start}.raw
    end.
    (<command),<parameters
)
