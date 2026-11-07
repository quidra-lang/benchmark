split_region =: 4 : 0
    'rx ry width height' =. 4{.y{Regions
    verticalfits =. width>:2*MinimumSize
    horizontalfits =. height>:2*MinimumSize
    if. (x=MaximumSplit)+.-.verticalfits+.horizontalfits do.
        Regions =: (#Leaves) (<y,6)}Regions
        Leaves =: Leaves,y
        i.0 return.
    end.
    if. verticalfits*.horizontalfits do.
        if. (4*width)>:5*height do. vertical =. 1
        elseif. (4*height)>:5*width do. vertical =. 0
        else. vertical =. 0=2|draw '' end.
    else. vertical =. verticalfits end.
    if. vertical do.
        cut =. MinimumSize+rnd 1+width-2*MinimumSize
        first =. rx,ry,cut,height
        second =. (rx+cut),ry,(width-cut),height
    else.
        cut =. MinimumSize+rnd 1+height-2*MinimumSize
        first =. rx,ry,width,cut
        second =. rx,(ry+cut),width,height-cut
    end.
    firstindex =. #Regions
    secondindex =. firstindex+1
    Regions =: Regions,first,_1 _1 _1
    Regions =: Regions,second,_1 _1 _1
    Regions =: firstindex (<y,4)}Regions
    Regions =: secondindex (<y,5)}Regions
    (x+1)split_region firstindex
    (x+1)split_region secondindex
    i.0
)
make_room =: 3 : 0
    'rx ry width height' =. 4{.y{Regions
    rw =. RoomMinimum+rnd 1+(RoomMaximum<.width-1)-RoomMinimum
    rh =. RoomMinimum+rnd 1+(RoomMaximum<.height-1)-RoomMinimum
    left =. rx+rnd width-rw
    top =. ry+rnd height-rh
    for_row. top+i.rh do.
        for_column. left+i.rw do.
            if. (row=top)+.row=top+rh-1 do. symbol =. '-'
            elseif. (column=left)+.column=left+rw-1 do. symbol =. '|'
            else. symbol =. '.' end.
            Terrain =: symbol (cell_index column,row)}Terrain
        end.
    end.
    left,top,rw,rh
)
room_center =: 3 : '(2{.y)+(2 3{y)div 2'
carve =: 3 : 0
    index =. cell_index y
    symbol =. index{Terrain
    if. symbol=' ' do. Terrain =: '#' index}Terrain
    elseif. symbol e.'-|' do. Terrain =: '+' index}Terrain end.
    i.0
)
inclusive_span =: 4 : 0
    if. y>:x do. x+i.1+y-x
    else. x-i.1+x-y end.
)
dig_corridor =: 3 : 0
    'ax ay bx by horizontal' =. y
    if. horizontal do.
        for_column. ax inclusive_span bx do. carve column,ay end.
        for_row. ay inclusive_span by do. carve bx,row end.
    else.
        for_row. ay inclusive_span by do. carve ax,row end.
        for_column. ax inclusive_span bx do. carve column,by end.
    end.
    i.0
)
connect_region =: 3 : 0
    region =. y{Regions
    if. (6{region)>:0 do. ,6{region return. end.
    first =. connect_region 4{region
    second =. connect_region 5{region
    besta =. bestb =. _1
    bestdistance =. 0
    for_a. first do.
        acenter =. room_center a{Rooms
        for_b. second do.
            bcenter =. room_center b{Rooms
            distance =. +/|acenter-bcenter
            if. (besta=_1)+.distance<bestdistance do.
                besta =. a
                bestb =. b
                bestdistance =. distance
            end.
        end.
    end.
    horizontal =. 0=2|draw ''
    dig_corridor (room_center besta{Rooms),(room_center bestb{Rooms),horizontal
    first,second
)
draw_interior_cell =: 3 : 0
    'left top width height' =. y{Rooms
    column =. left+1+rnd width-2
    row =. top+1+rnd height-2
    column,row
)
draw_room_cell =: 3 : 0
    room =. rnd #Rooms
    room,draw_interior_cell room
)
generate_terrain =: 3 : 0
    Terrain =: (MapWidth*MapHeight)$' '
    Memory =: Terrain
    Regions =: ,:0 0,MapWidth,MapHeight,_1 _1 _1
    Leaves =: 0$0
    0 split_region 0
    Rooms =: 0 4$0
    for_leaf. Leaves do. Rooms =: Rooms,make_room leaf end.
    connect_region 0
    'ArrivalRoom ax ay' =: draw_room_cell ''
    Arrival =: ax,ay
    Terrain =: '<' (cell_index Arrival)}Terrain
    other =. rnd (#Rooms)-1
    if. other>:ArrivalRoom do. other =. other+1 end.
    Target =: draw_interior_cell other
    i.0
)
