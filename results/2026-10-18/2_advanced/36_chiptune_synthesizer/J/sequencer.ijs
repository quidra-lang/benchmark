samples_per_tick =: 4 : '(5*x)intdiv 2*y'
next_row =: 4 : 0
    'position row' =. y
    jump =. _1
    pattern_break =. _1
    for_cell. x do.
        code =. 3{cell
        argument =. 4{cell
        if. code do.
            name =. (code-1){::EffectNames
            if. (name-:'F')*.argument=0 do.
                _1 return.
            elseif. name-:'B' do.
                jump =. argument
            elseif. name-:'D' do.
                pattern_break =. argument
            end.
        end.
    end.
    if. (jump<0)*.pattern_break<0 do.
        if. row<63 do.
            (64*position)+row+1
        else.
            64*position+1
        end.
    else.
        if. jump<0 do.
            jump =. position+1
        end.
        if. (pattern_break<0)+.pattern_break>:64 do.
            pattern_break =. 0
        end.
        (64*jump)+pattern_break
    end.
)
reachable_rows =: 3 : 0
    reached =. (#y)$0
    current =. 0
    while. (current>:0)*.current<#y do.
        if. current{reached do.
            break.
        end.
        reached =. 1 current}reached
        current =. current{y
    end.
    reached
)
