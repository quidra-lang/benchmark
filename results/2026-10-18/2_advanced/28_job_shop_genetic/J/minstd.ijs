draw =: 3 : 0
    RngState =: 2147483647|48271*RngState
    RngState
)
below =: 3 : 'y|draw 0'
chance =: 3 : '((1{y)|draw 0)<0{y'
shuffle =: 3 : 0
    values =. y
    for_size. |.2+i.(#values)-1 do.
        position =. below size
        held =. (size-1){values
        values =. (position{values)(size-1)}values
        values =. held position}values
    end.
    values
)
