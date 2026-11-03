line_class =: 3 : 0
    'slack last' =. y
    if. last do.
        1
    elseif. slack<:1 do.
        0
    elseif. slack<:3 do.
        1
    elseif. slack<:6 do.
        2
    else.
        3
    end.
)
slack =: 4 : 0
    'start end' =. y
    capacity =. 4{::x
    if. start=0 do.
        capacity =. 3{::x
    end.
    capacity-((end{1{::x)-start{0{::x)
)
line_cost =: 4 : 0
    'start end previous costs' =. y
    space =. x slack start,end
    last =. end=(#0{::x)-1
    current =. line_class space,last
    cost =. 0{costs
    if. space<0 do.
        cost =. cost+5{costs
    elseif. -.last do.
        cost =. cost+space*space
    end.
    midword =. 2{::x
    if. end{midword do.
        cost =. cost+1{costs
        if. start{midword do.
            cost =. cost+2{costs
        end.
    end.
    if. last*.start{midword do.
        cost =. cost+3{costs
    end.
    if. 2<:|current-previous do.
        cost =. cost+4{costs
    end.
    cost
)
break_text =: 3 : 0
    'metrics method costs' =. y
    finish =. (#0{::metrics)-1
    positions =. i.0
    if. method-:'greedy' do.
        start =. 0
        previous_class =. 1
        total =. 0
        while. start<finish do.
            chosen =. start+1
            if. 0<:metrics slack start,chosen do.
                for_end. (chosen+1)+i.finish-chosen do.
                    if. 0>metrics slack start,end do.
                        break.
                    end.
                    chosen =. end
                end.
            end.
            total =. total+metrics line_cost (<start),(<chosen),(<previous_class),<costs
            previous_class =. line_class (metrics slack start,chosen),chosen=finish
            positions =. positions,chosen
            start =. chosen
        end.
        (<positions),<total return.
    end.
    totals =. ((finish+1),4)$_1
    previous =. ($totals)$_1
    classes =. ($totals)$_1
    totals =. 0 (<0,1)}totals
    for_end. 1+i.finish do.
        for_start. |.i.end do.
            space =. metrics slack start,end
            if. (space<0)*.end~:start+1 do.
                break.
            end.
            current_class =. line_class space,end=finish
            for_previous_class. i.4 do.
                before =. (<start,previous_class){totals
                if. before<0 do.
                    continue.
                end.
                cost =. before+metrics line_cost (<start),(<end),(<previous_class),<costs
                coordinate =. <end,current_class
                best =. coordinate{totals
                take =. (best<0)+.cost<best
                if. cost=best do.
                    take =. (start<coordinate{previous)+.((start=coordinate{previous)*.previous_class<coordinate{classes)
                end.
                if. take do.
                    totals =. cost coordinate}totals
                    previous =. start coordinate}previous
                    classes =. previous_class coordinate}classes
                end.
            end.
        end.
    end.
    position =. finish
    current_class =. 1
    total =. (<position,current_class){totals
    while. position>0 do.
        positions =. positions,position
        coordinate =. <position,current_class
        position =. coordinate{previous
        current_class =. coordinate{classes
    end.
    (<|.positions),<total
)
