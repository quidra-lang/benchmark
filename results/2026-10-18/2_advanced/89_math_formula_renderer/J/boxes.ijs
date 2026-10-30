new_box =: 3 : 0
    number =. #BoxPool
    box =. y,(<0$a:),<0$a:
    BoxPool =: BoxPool,<box
    number
)
box_width =: 3 : '0{::y{::BoxPool'
box_height =: 3 : '1{::y{::BoxPool'
box_baseline =: 3 : '2{::y{::BoxPool'
box_descent =: 3 : '(box_height y)-(1+box_baseline y)'
add_child =: 4 : 0
    box =. x{::BoxPool
    children =. (4{::box),<y
    box =. (<children)4}box
    BoxPool =: (<box)x}BoxPool
    x
)
add_string =: 4 : 0
    box =. x{::BoxPool
    strings =. (5{::box),<y
    box =. (<strings)5}box
    BoxPool =: (<box)x}BoxPool
    x
)
large_glyph =: 3 : 0
    select. y
    case. '\sum' do. '\--';' > ';'/--'
    case. '\prod' do. '___';'| |';'| |'
    case. '\int' do. ' /';' |';'/ '
    end.
)
delimiter_glyph =: 4 : 0
    delimiter =. x
    height =. y
    if. delimiter-:,'.' do.
        0$a: return.
    end.
    character =. {:delimiter
    if. height=1 do.
        ,<,character return.
    end.
    if. (1=#delimiter)*.character e.'[]|' do.
        height$<,character return.
    end.
    left =. (delimiter-:,'(')+.delimiter-:'\{'
    first =. '\'
    last =. '/'
    if. left do.
        first =. '/'
        last =. '\'
    end.
    glyph =. (<,first),((height-2)$<,'|'),<,last
    if. ((<delimiter)e.'\{';'\}')*.height>:3 do.
        middle =. (height-1)intdiv 2
        character =. '>'
        if. left do.
            character =. '<'
        end.
        glyph =. (<,character)middle}glyph
    end.
    glyph
)
command_display =: 3 : '(CommandKeys i.<y){::CommandDisplays'
command_type =: 3 : '(CommandKeys i.<y){CommandTypes'
symbol_type =: 3 : 0
    character =. {.y
    if. character e.'+-*' do. 2
    elseif. character e.'=<>:' do. 3
    elseif. character e.'([' do. 4
    elseif. character e.')]!' do. 5
    elseif. character e.',;' do. 6
    else. 0 end.
)
