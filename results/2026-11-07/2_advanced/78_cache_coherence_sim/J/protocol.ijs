dirty_state =: 3 : 'y e.''MO'''
requester =: 4 : 0
    'old operation other_copy' =. y
    if. x-:'VI' do.
        if. operation=0 do.
            if. old='I' do.
                (<0),<'V' return.
            end.
            (<_1),<'V' return.
        end.
        new =. 'V'
        if. old='I' do.
            new =. 'I'
        end.
        (<3),<new return.
    end.
    if. old='I' do.
        if. operation=1 do.
            (<1),<'M' return.
        end.
        new =. 'S'
        if. ((<x)e.;:'MESI MOESI')*.-.other_copy do.
            new =. 'E'
        end.
        (<0),<new return.
    end.
    if. operation=0 do.
        (<_1),<old return.
    end.
    if. old e.'ME' do.
        (<_1),<'M'
    else.
        (<2),<'M'
    end.
)
snoop =: 4 : 0
    'old transaction' =. y
    if. x-:'VI' do.
        if. transaction=0 do.
            (<'V'),(<0),<0
        else.
            (<'I'),(<0),<0
        end.
        return.
    end.
    if. transaction=0 do.
        if. old='M' do.
            if. x-:'MOESI' do.
                (<'O'),(<1),<0
            else.
                (<'S'),(<1),<1
            end.
        elseif. old='O' do.
            (<'O'),(<1),<0
        else.
            (<'S'),(<0),<0
        end.
    elseif. transaction=1 do.
        (<'I'),(<dirty_state old),<0
    else.
        (<'I'),(<0),<0
    end.
)
