r_block =: 0&{::
r_parent =: 1&{::
r_utxo =: 2&{::
r_txfees =: 3&{::
r_source =: 4&{::
r_work =: 5&{::
r_fees =: +/@r_txfees
r_height =: b_height@r_block
r_hash =: b_hash@r_block
reward =: 3 : 0
    'height amount interval' =. y
    for_i. i.height intdiv interval do. amount =. amount intdiv 2 end.
    amount
)
ancestor =: 4 : 0
    'cursor height' =. y
    while. height<r_height cursor{::x do. cursor =. r_parent cursor{::x end.
    cursor
)
chain_to =: 4 : 0
    reverse =. i.0
    cursor =. y
    while. cursor>:0 do.
        reverse =. reverse,cursor
        cursor =. r_parent cursor{::x
    end.
    |.reverse
)
fork_point =: 4 : 0
    'first second' =. y
    height =. (r_height first{::x)<.r_height second{::x
    first =. x ancestor first,height
    second =. x ancestor second,height
    while. first~:second do.
        first =. r_parent first{::x
        second =. r_parent second{::x
    end.
    first
)
median_time =: 4 : 0
    cursor =. y
    times =. i.0
    while. (cursor>:0)*.3>#times do.
        times =. times,b_time r_block cursor{::x
        cursor =. r_parent cursor{::x
    end.
    ((<:#times)intdiv 2){/:~times
)
required_difficulty =: 4 : 0
    'parent initial interval target' =. y
    record =. parent{::x
    height =. >:r_height record
    difficulty =. b_difficulty r_block record
    if. height=1 do. initial return. end.
    if. interval|height do. difficulty return. end.
    first =. x ancestor parent,height-interval
    span =. (b_time r_block record)-b_time r_block first{::x
    expected =. target*<:interval
    if. (2*span)<expected do. 2<.>:difficulty return. end.
    if. span>2*expected do. 0>.difficulty-1 return. end.
    difficulty
)
