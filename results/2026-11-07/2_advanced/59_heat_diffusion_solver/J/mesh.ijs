floor_div =: 4 : '<.(x:x)%x:y'
split_words =: 3 : '<;._1 '' '',y'
read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
read_plate =: 3 : 0
    rows =. read_lines 'plate.txt'
    header =. split_words 0{::rows
    width =. ".0{::header
    height =. ".1{::header
    dx =. 0.0+".2{::header
    thickness =. 0.0+".3{::header
    codes =. ;}.rows
    neighbors =. 0 4$0
    for_row. i.height do.
        for_column. i.width do.
            point =. column+width*row
            left =. right =. top =. bottom =. _1
            if. column do. left =. point-1 end.
            if. (column+1)<width do. right =. point+1 end.
            if. row do. top =. point-width end.
            if. (row+1)<height do. bottom =. point+width end.
            neighbors =. neighbors,left,right,top,bottom
        end.
    end.
    (<width),(<height),(<dx),(<thickness),(<codes),<neighbors
)
cell_number =: 3 : 0
    'row column' =. y
    column+Width*row
)
coordinates =: 3 : '(y floor_div Width),Width|y'
segment_faces =: 4 : 0
    'first last' =. y
    result =. 0 2$0
    for_coordinate. first+i.1+last-first do.
        select. x
        case. 'top' do. point =. coordinate
            direction =. 2
        case. 'bottom' do. point =. coordinate+Width*Height-1
            direction =. 3
        case. 'left' do. point =. Width*coordinate
            direction =. 0
        case. 'right' do. point =. (Width-1)+Width*coordinate
            direction =. 1
        end.
        result =. result,point,direction
    end.
    result
)
source_cells =: 3 : 0
    'first_row first_column last_row last_column' =. y
    result =. i.0
    for_row. first_row+i.1+last_row-first_row do.
        for_column. first_column+i.1+last_column-first_column do.
            result =. result,column+Width*row
        end.
    end.
    result
)
