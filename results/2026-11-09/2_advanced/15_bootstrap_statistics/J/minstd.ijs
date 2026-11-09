draw =: 3 : 0
    RandomState =: 2147483647|48271*RandomState
    RandomState
)
draw_below =: 3 : 'y|draw '''''
shuffle =: 3 : 0
    items =. y
    for_index. |.1+i.(#items)-1 do.
        other =. draw_below index+1
        first =. index{items
        second =. other{items
        items =. second index}items
        items =. first other}items
    end.
    items
)
