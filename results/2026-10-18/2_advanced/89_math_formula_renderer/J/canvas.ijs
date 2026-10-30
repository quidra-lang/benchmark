trim_spaces =: 3 : 0
    text =. y
    while. #text do.
        if. ' '~:{:text do.
            break.
        end.
        text =. }:text
    end.
    text
)
walk_box =: 3 : 0
    'number xx yy level role' =. y
    box =. number{::BoxPool
    WalkRows =: WalkRows,<y
    for_child. 4{::box do.
        'child dx dy child_role' =. >child
        walk_box(<child),(<xx+dx),(<yy+dy),(<level+1),<child_role
    end.
)
walk_roots =: 3 : 0
    WalkRows =: 0$a:
    for_root. y do.
        'number xx yy' =. root
        walk_box(<number),(<xx),(<yy),(<0),<''
    end.
    WalkRows
)
draw_formula =: 3 : 0
    'roots width height' =. y
    grid =. (width*height)$' '
    for_row. walk_roots roots do.
        'number xx yy level role' =. >row
        box =. number{::BoxPool
        for_string. 5{::box do.
            'text dx dy' =. >string
            for_i. I.text~:' ' do.
                index =. (xx+dx+i)+width*(yy+dy)
                grid =. (i{text)index}grid
            end.
        end.
    end.
    lines =. 0$a:
    for_i. i.height do.
        lines =. lines,<trim_spaces width{.(i*width)}.grid
    end.
    lines
)
box_lines =: 3 : 0
    lines =. 0$a:
    kinds =. 0$a:
    depth =. 0
    for_row. walk_roots y do.
        'number xx yy level role' =. >row
        'width height baseline description children strings' =. number{::BoxPool
        line =. ((2*level)$' '),role,description,' x=',(integer xx),' y=',integer yy
        lines =. lines,<line,' w=',(integer width),' h=',(integer height),' b=',integer baseline
        depth =. depth>.level+1
        kinds =. kinds,<(description i.' '){.description
    end.
    (<lines),(<depth),<kinds
)
