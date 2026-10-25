ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
Lowercase =: 'abcdefghijklmnopqrstuvwxyz'
div =: 4 : '_1 x:<.(x:x)%x:y'
num =: 3 : '10#.Digits i.y'
signed_num =: 3 : 0
    if. '-'={.y do. -num }.y else. num y end.
)
number =: 3 : 0
    if. y<0 do. '-',number -y return. end.
    text =. ''
    while. y>0 do.
        text =. ((10|y){Digits),text
        y =. y div 10
    end.
    if. #text do. text else. '0' end.
)
split =: 4 : 0
    parts =. 0$a:
    while. 1 do.
        position =. y i.x
        parts =. parts,<position{.y
        if. position=#y do. parts return. end.
        y =. (position+1)}.y
    end.
)
join =: 4 : 0
    text =. ''
    for_index. i.#y do.
        if. index do. text =. text,x end.
        text =. text,index{::y
    end.
    text
)
read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
empty_table =: 3 : '0 2$a:'
table_keys =: 3 : '0{"1 y'
has_key =: 4 : '(<x)e.table_keys y'
get_key =: 4 : '((table_keys y)i.<x){::1{"1 y'
put_key =: 4 : 0
    'key value' =. x
    position =. (table_keys y)i.<key
    if. position<#y do. (<value) (<position,1)}y
    else. y,1 2$(<key),<value end.
)
record =: 4 : '('' '' split x),.y'
load SourceDirectory,'canvas.ijs'
load SourceDirectory,'primitives.ijs'
load SourceDirectory,'clipping.ijs'
load SourceDirectory,'fill.ijs'
load SourceDirectory,'ppm_writer.ijs'
PenCommands =: ' ' split 'LINE RECT CIRCLE ELLIPSE POLYLINE POLYGON PATH'
BrushCommands =: ' ' split 'FILLRECT FILLCIRCLE FILLELLIPSE FILLPOLYGON FILLPATH FLOOD TEXT'
StateCommands =: ' ' split 'TRANSLATE SCALE ROTATE SAVE RESTORE CLIP NOCLIP USE'
Commands =: PenCommands,BrushCommands,(<'ERASE'),StateCommands
ErrorNames =: ' ' split 'unknown_command bad_arguments unknown_style unknown_symbol unknown_glyph bad_value stack_empty'
PathLetters =: 'MmLlHhVvQqCcZz'
PathArity =: 2 2 2 2 1 1 1 1 4 4 6 6 0 0
trim_spaces =: 3 : 0
    indices =. I.y~:' '
    if. #indices do. (1+({:indices)-{.indices){.({.indices)}.y else. '' end.
)
words =: 3 : 0
    parts =. ' ' split trim_spaces y
    parts#~0<#&>parts
)
is_integer =: 3 : 0
    if. 0=#y do. 0 return. end.
    if. '-'={.y do. y =. }.y end.
    (0<#y)*.*./y e.Digits
)
all_integers =: 3 : '*./is_integer&>y'
text_line =: 3 : 0
    fields =. 0$a:
    for_box. y do.
        value =. >box
        if. 2~:3!:0 value do. value =. number value end.
        fields =. fields,<value
    end.
    ' ' join fields
)
intersect_rect =: 4 : '((0{x)>.0{y),((1{x)>.1{y),((2{x)<.2{y),(3{x)<.3{y'
empty_rect =: 3 : '((0{y)>2{y)+.(1{y)>3{y'
contains =: 4 : '((0{y)>:0{x)*.((0{y)<:2{x)*.((1{y)>:1{x)*.(1{y)<:3{x'
rect_pixels =: 3 : 0
    if. empty_rect y do. 0$0 return. end.
    'x0 y0 x1 y1' =. y
    pixels =. 0$0
    for_py. y0+i.1+y1-y0 do. pixels =. pixels,(py*Width)+x0+i.1+x1-x0 end.
    pixels
)
points_pixels =: 3 : 0
    pixels =. 0$0
    for_point. y do. if. Clip contains point do. pixels =. pixels,(Width*1{point)+0{point end. end.
    ~.pixels
)
bounding_box =: 3 : 0
    if. 0=#y do. 0$0 return. end.
    px =. Width|y
    py =. y div Width
    (<./px),(<./py),(>./px),>./py
)
box_text =: 3 : 0
    box =. bounding_box y
    if. #box do. ' ' join number&.><"0 box else. 'none' end.
)
open_segments =: 4 : 0
    points =. y
    segments =. 0$a:
    for_index. i.0>.(#points)-1 do. segments =. segments,<(index+i.2){points end.
    if. x do. segments =. segments,<({:points),:{.points end.
    segments
)
parse_path =: 3 : 0
    commands =. 0$a:
    position =. 0
    previous =. 'Z'
    while. position<#y do.
        letter =. position{::y
        if. (1~:#letter)+.-.letter e.PathLetters do. a: return. end.
        count =. (PathLetters i.letter){PathArity
        if. (position+count)>:#y do. a: return. end.
        values =. count{.(position+1)}.y
        if. -.all_integers values do. a: return. end.
        if. (previous e.'Zz')*.-.letter e.'Mm' do. a: return. end.
        commands =. commands,<'letter values' record (<letter),<signed_num&>values
        previous =. letter
        position =. position+count+1
    end.
    if. #commands do. commands else. a: end.
)
read_body =: 3 : 0
    body =. 0$a:
    while. 1 do.
        item =. ReadPosition{::Instructions
        ReadPosition =: ReadPosition+1
        key =. 'keyword' get_key item
        if. (<key)e.'END';'ENDREPEAT' do. 'body end' record (<body),<'line' get_key item return. end.
        if. key-:'REPEAT' do.
            values =. signed_num&>'arguments' get_key item
            nested =. read_body ''
            item =. 'keyword count dx dy body' record (<'REPEAT'),(<0{values),(<1{values),(<2{values),<'body' get_key nested
        end.
        body =. body,<item
    end.
)
load_inputs =: 3 : 0
    Colors =: Pens =: Brushes =: Symbols =: Glyphs =: empty_table ''
    Layers =: Executions =: Instructions =: 0$a:
    UsedColors =: UsedPens =: UsedBrushes =: 0$a:
    for_box. read_lines 'styles.txt' do.
        line =. >box
        if. 0=#line do. continue. end.
        if. '#'={.line do. continue. end.
        fields =. words line
        'kind name' =. 2{.fields
        values =. 2}.fields
        select. kind
        case. 'color' do. Colors =: ((<name),<signed_num&>values) put_key Colors
        case. 'pen' do.
            pen =. 'width color on off' record (<signed_num 0{::values),(1{values),(<signed_num 2{::values),<signed_num 3{::values
            Pens =: ((<name),<pen) put_key Pens
        case. 'brush' do.
            brush =. 'colors axis rule' record (<,0{values),( <''),1{values
            Brushes =: ((<name),<brush) put_key Brushes
        case. 'gradient' do.
            brush =. 'colors axis rule' record (<2{.values),(2{values),3{values
            Brushes =: ((<name),<brush) put_key Brushes
        end.
    end.
    lines =. read_lines 'font.txt'
    'FontWidth FontHeight' =: num&>}.words 0{::lines
    position =. 1
    while. position<#lines do.
        glyph =. 1{::words position{::lines
        dots =. empty_points ''
        for_row. i.FontHeight do.
            text =. (position+row+1){::lines
            for_column. I.text='#' do. dots =. dots,column,row end.
        end.
        Glyphs =: ((<glyph),<dots) put_key Glyphs
        position =. position+FontHeight+1
    end.
    lines =. read_lines 'scene.txt'
    for_index. i.#lines do.
        text =. trim_spaces index{::lines
        if. 0=#text do. continue. end.
        if. '#'={.text do. continue. end.
        fields =. words text
        Instructions =: Instructions,<'line keyword arguments' record (<index+1),(0{fields),<}.fields
    end.
    ReadPosition =: 0
    while. ReadPosition<#Instructions do.
        item =. ReadPosition{::Instructions
        ReadPosition =: ReadPosition+1
        key =. 'keyword' get_key item
        fields =. 'arguments' get_key item
        if. key-:'CANVAS' do.
            Width =: num 0{::fields
            Height =: num 1{::fields
            PixelCount =: Width*Height
            BackgroundName =: 2{::fields
            Background =: BackgroundName get_key Colors
        else.
            block =. read_body ''
            name =. 0{::fields
            if. key-:'LAYER' do. Layers =: Layers,<layer_record (<name),(<num 1{::fields),(2{fields),<'body' get_key block
            else. Symbols =: ((<name),<block) put_key Symbols end.
        end.
    end.
    Screen =: 0 0,(Width-1),Height-1
    Uses =: (#Symbols)$0
    UsedColors =: <BackgroundName
    Probes =: 0$a:
    for_box. }.read_lines 'probes.txt' do.
        fields =. words >box
        Probes =: Probes,<'kind values' record (0{fields),<signed_num&>}.fields
    end.
    i.0
)
snapshot =: 3 : '(<Matrix),(<Clip),<Stack'
rollback =: 3 : 0
    'Matrix Clip Stack' =: y
    i.0
)
transform_point =: 3 : 0
    'a b c d e f' =. Matrix
    'px py' =. y
    ((a*px)+(b*py)+e),(c*px)+(d*py)+f
)
device_rect =: 3 : 0
    first =. transform_point 2{.y
    last =. transform_point 2}.y
    (first<.last),first>.last
)
translate_state =: 3 : 0
    'a b c d e f' =. Matrix
    'dx dy' =. y
    Matrix =: a,b,c,d,(e+(a*dx)+b*dy),f+(c*dx)+d*dy
    i.0
)
valid_form =: 4 : 0
    key =. x
    args =. y
    names =. ' ' split 'LINE RECT FILLRECT CIRCLE FILLCIRCLE ELLIPSE FILLELLIPSE FLOOD ERASE TRANSLATE SCALE ROTATE SAVE RESTORE NOCLIP CLIP USE'
    forms =. 17 2$5 1 5 1 5 1 4 1 4 1 5 1 5 1 3 1 4 0 2 0 2 0 1 0 0 0 0 0 0 0 4 0 3 1
    index =. names i.<key
    if. index<#names do.
        'count first' =. index{forms
        if. count~:#args do. 0 return. end.
        all_integers first}.args return.
    end.
    if. key-:'TEXT' do.
        if. 5~:#args do. 0 return. end.
        all_integers 2{.}.args return.
    end.
    if. (<key)e.'POLYLINE';'POLYGON';'FILLPOLYGON' do.
        if. (#args)<2 do. 0 return. end.
        if. -.all_integers }.args do. 0 return. end.
        (#args)=2+2*signed_num 1{::args return.
    end.
    if. (#args)<2 do. 0 return. end.
    if. -.is_integer 1{::args do. 0 return. end.
    -.a:-:parse_path 2}.args
)
check_command =: 3 : 0
    key =. 'keyword' get_key y
    args =. 'arguments' get_key y
    if. -. (<key)e.Commands do. 'unknown_command' return. end.
    if. -.key valid_form args do. 'bad_arguments' return. end.
    if. (<key)e.PenCommands do. if. -. (0{::args) has_key Pens do. 'unknown_style' return. end. end.
    if. (<key)e.BrushCommands do. if. -. (0{::args) has_key Brushes do. 'unknown_style' return. end. end.
    if. key-:'USE' do.
        name =. 0{::args
        if. -.name has_key Symbols do. 'unknown_symbol' return. end.
        symbol =. name get_key Symbols
        if. ('end' get_key symbol)>:'line' get_key y do. 'unknown_symbol' return. end.
    end.
    if. key-:'TEXT' do.
        for_character. 4{::args do.
            character =. ,character
            if. (character~:'_')*.-.character has_key Glyphs do. 'unknown_glyph' return. end.
        end.
    end.
    if. (key-:'RESTORE')*.0=#Stack do. 'stack_empty' return. end.
    valid =. 1
    select. key
    case. 'CIRCLE';'FILLCIRCLE' do. valid =. (signed_num 3{::args)>:1
    case. 'ELLIPSE';'FILLELLIPSE' do. valid =. *./(signed_num&>3}.args)>:1
    case. 'POLYLINE' do. valid =. (signed_num 1{::args)>:2
    case. 'POLYGON';'FILLPOLYGON' do. valid =. (signed_num 1{::args)>:3
    case. 'PATH';'FILLPATH' do. count =. signed_num 1{::args
        valid =. (count>:1)*.count<:32
    case. 'FLOOD' do. valid =. Clip contains transform_point signed_num&>}.args
    case. 'TEXT' do. valid =. (3{args)e.'left';'center';'right'
    case. 'SCALE' do. valid =. *./0~:signed_num&>args
    case. 'CLIP' do. valid =. -.empty_rect Clip intersect_rect device_rect signed_num&>args
    end.
    if. valid do. '' else. 'bad_value' end.
)
transform_points =: 3 : 0
    output =. empty_points ''
    for_point. y do. output =. output,transform_point point end.
    output
)
build_subpaths =: 4 : 0
    segments =. x
    commands =. y
    subpaths =. 0$a:
    current =. start =. 0 0
    for_box. commands do.
        command =. >box
        letter =. 'letter' get_key command
        kind =. toupper letter
        if. kind-:'Z' do.
            subpath =. ((<'closed'),<1) put_key >{:subpaths
            subpaths =. (<subpath) (<:#subpaths)}subpaths
            current =. start
            continue.
        end.
        offset =. 0 0
        if. letter-:tolower letter do. offset =. current end.
        values =. 'values' get_key command
        if. kind-:'H' do. points =. 1 2$(({.values)+{.offset),{:current
        elseif. kind-:'V' do. points =. 1 2$({.current),({.values)+{:offset
        else. points =. offset+"1 (((#values) div 2),2)$values end.
        device =. transform_points points
        if. kind-:'M' do.
            subpaths =. subpaths,<'points closed' record (<device),<0
            start =. {.points
        else.
            subpath =. >{:subpaths
            sequence =. 'points' get_key subpath
            if. (<kind)e.'L';'H';'V' do. sequence =. sequence,device
            else. controls =. ({:sequence),device
                sequence =. sequence,}.controls bezier_points segments end.
            subpath =. ((<'points'),<sequence) put_key subpath
            subpaths =. (<subpath) (<:#subpaths)}subpaths
        end.
        current =. {:points
    end.
    subpaths
)
expand_points =: 4 : 0
    pixels =. 0$0
    for_point. y do. pixels =. pixels,points_pixels point expand_square x end.
    ~.pixels
)
stroke =: 4 : 0
    pen =. x
    points =. empty_points ''
    for_box. y do.
        segment =. >box
        clipped =. clip_segment (<{.segment),(<{:segment),<Clip
        if. #clipped do. points =. points,({.clipped) bresenham {:clipped end.
    end.
    off =. 'off' get_key pen
    if. off>0 do.
        on =. 'on' get_key pen
        points =. points#~on>(on+off)|i.#points
    end.
    ('width' get_key pen) expand_points points
)
shape =: 4 : 0
    key =. x
    values =. y
    center =. transform_point 2{.values
    if. (<key)e.'CIRCLE';'FILLCIRCLE' do. radii =. 2#2{values
    else. radii =. 2}.values end.
    matrix =. |4{.Matrix
    rx =. ((0{matrix)*0{radii)+(1{matrix)*1{radii
    ry =. ((2{matrix)*0{radii)+(3{matrix)*1{radii
    if. ((<key)e.'CIRCLE';'FILLCIRCLE')*.rx=ry do. points =. circle_points rx
    else. points =. ellipse_points rx,ry end.
    (<center),<points
)
text_coverage =: 3 : 0
    'xt yt alignment text' =. y
    px =. signed_num xt
    py =. signed_num yt
    advance =. FontWidth+1
    extent =. ((#text)*advance)-1
    if. alignment-:'left' do. left =. px
    elseif. alignment-:'center' do. left =. px-extent div 2
    else. left =. (px-extent)+1 end.
    pixels =. 0$0
    for_index. i.#text do.
        character =. ,index{text
        if. character-:'_' do. continue. end.
        origin =. left+index*advance
        for_dot. character get_key Glyphs do.
            first =. transform_point (origin,py)+dot
            last =. transform_point (origin,py)+dot+1
            rect =. (first<.last),(first>.last)-1
            pixels =. pixels,rect_pixels Clip intersect_rect rect
        end.
    end.
    ~.pixels
)
coverage =: 3 : 0
    'key args style' =. y
    if. key-:'TEXT' do. text_coverage args return. end.
    if. key-:'FLOOD' do. flood_fill (<transform_point signed_num&>args),<Clip return. end.
    if. (<key)e.'CIRCLE';'ELLIPSE';'FILLCIRCLE';'FILLELLIPSE' do.
        'center points' =. key shape signed_num&>args
        if. (<key)e.PenCommands do. ('width' get_key style) expand_points center+"1 points return. end.
        fill_shape (<center),(<points),<Clip return.
    end.
    if. key-:'FILLRECT' do. rect_pixels Clip intersect_rect device_rect signed_num&>args return. end.
    if. (<key)e.'PATH';'FILLPATH' do.
        subpaths =. (signed_num 0{::args) build_subpaths parse_path }.args
        if. key-:'FILLPATH' do.
            sequences =. 0$a:
            for_box. subpaths do. sequences =. sequences,<('points' get_key >box) clip_polygon Clip end.
            fill_polygons (<sequences),(<'rule' get_key style),<Clip return.
        end.
        segments =. 0$a:
        for_box. subpaths do.
            subpath =. >box
            segments =. segments,('closed' get_key subpath) open_segments 'points' get_key subpath
        end.
    elseif. (<key)e.'POLYLINE';'POLYGON';'FILLPOLYGON' do.
        values =. signed_num&>}.args
        points =. transform_points (((#values) div 2),2)$values
        if. key-:'FILLPOLYGON' do.
            sequences =. <points clip_polygon Clip
            fill_polygons (<sequences),(<'rule' get_key style),<Clip return.
        end.
        segments =. (key-:'POLYGON') open_segments points
    elseif. key-:'RECT' do.
        'x0 y0 x1 y1' =. device_rect signed_num&>args
        points =. 4 2$x0,y0,x1,y0,x1,y1,x0,y1
        segments =. 1 open_segments points
    else.
        points =. transform_points 2 2$signed_num&>args
        segments =. <points
    end.
    style stroke segments
)
paint_pixels =: 3 : 0
    'pixels style pen line' =. y
    if. 0=#pixels do. i.0 return. end.
    if. pen do. first =. ('color' get_key style) get_key Colors
    else. first =. (0{::'colors' get_key style) get_key Colors end.
    colors =. layer_get 'colors'
    gradient =. 0
    if. -.pen do. gradient =. 0<#'axis' get_key style end.
    if. gradient do.
        second =. (1{::'colors' get_key style) get_key Colors
        box =. bounding_box pixels
        axis =. ('axis' get_key style)-:'y'
        length =. ((axis+2){box)-axis{box
    end.
    for_id. pixels do.
        color =. first
        if. gradient do.
            if. length>0 do.
                if. axis=0 do. position =. Width|id else. position =. id div Width end.
                offset =. position-axis{box
                color =. first+((second-first)*offset) round_ratio length
            end.
        end.
        colors =. color id}colors
    end.
    'colors' layer_set colors
    'painted' layer_set 1 pixels}layer_get 'painted'
    'lines' layer_set line pixels}layer_get 'lines'
    i.0
)
execute_body =: 3 : 0
    for_box. y do.
        item =. >box
        if. ('keyword' get_key item)-:'REPEAT' do.
            saved =. snapshot ''
            for_index. i.'count' get_key item do.
                rollback saved
                translate_state index*('dx' get_key item),'dy' get_key item
                execute_body 'body' get_key item
            end.
            rollback saved
        else. execute_command item end.
    end.
    i.0
)
execution_set =: 3 : 0
    'index key value' =. y
    execution =. ((<key),<value) put_key index{::Executions
    Executions =: (<execution) index}Executions
    i.0
)
execute_command =: 3 : 0
    command =. y
    key =. 'keyword' get_key command
    args =. 'arguments' get_key command
    line =. 'line' get_key command
    index =. #Executions
    execution =. 'sequence layer line keyword kind error pixels' record (<index+1),(<CurrentLayer),(<line),(<key),( <''),( <''),<0$0
    Executions =: Executions,<execution
    'commands' layer_add 1
    error =. check_command command
    if. #error do.
        execution_set (<index),(<'kind'),<'error'
        execution_set (<index),(<'error'),<error
        'errors' layer_add 1
        i.0 return.
    end.
    if. (<key)e.StateCommands do.
        execution_set (<index),(<'kind'),<'state'
        select. key
        case. 'TRANSLATE' do. translate_state signed_num&>args
        case. 'SCALE' do.
            scale =. signed_num&>args
            Matrix =: ((4{.Matrix)*0 1 0 1{scale),4}.Matrix
        case. 'ROTATE' do.
            for_turn. i.4|signed_num 0{::args do.
                'a b c d e f' =. Matrix
                Matrix =: b,(-a),d,(-c),e,f
            end.
        case. 'SAVE' do. Stack =: Stack,<(<Matrix),<Clip
        case. 'RESTORE' do.
            'Matrix Clip' =: >{:Stack
            Stack =: }:Stack
        case. 'CLIP' do. Clip =: Clip intersect_rect device_rect signed_num&>args
        case. 'NOCLIP' do. Clip =: Screen
        case. 'USE' do.
            name =. 0{::args
            symbolindex =. (table_keys Symbols)i.<name
            Uses =: (1+symbolindex{Uses) symbolindex}Uses
            saved =. snapshot ''
            translate_state signed_num&>}.args
            execute_body 'body' get_key name get_key Symbols
            rollback saved
        end.
        i.0 return.
    end.
    execution_set (<index),(<'kind'),<'drawing'
    if. key-:'ERASE' do.
        pixels =. rect_pixels Clip intersect_rect device_rect signed_num&>args
        painted =. layer_get 'painted'
        pixels =. pixels#~pixels{painted
        'painted' layer_set 0 pixels}painted
    else.
        pen =. (<key)e.PenCommands
        name =. 0{::args
        if. pen do. style =. name get_key Pens
        else. style =. name get_key Brushes end.
        pixels =. coverage (<key),(<}.args),<style
        paint_pixels (<pixels),(<style),(<pen),<line
        if. pen do.
            UsedPens =: ~.UsedPens,<name
            UsedColors =: ~.UsedColors,<'color' get_key style
        else.
            UsedBrushes =: ~.UsedBrushes,<name
            UsedColors =: ~.UsedColors,'colors' get_key style
        end.
    end.
    execution_set (<index),(<'pixels'),<pixels
    i.0
)
rank_colors =: 3 : 0
    columns =. {:$y
    if. 0=#y do. 'colors counts' record (<(0,columns)$0),<0$0 return. end.
    ordered =. (/:y){y
    starts =. 0,1+I.+./"1 (}.ordered)~:}:ordered
    counts =. ((}.starts),#ordered)-starts
    palette =. starts{ordered
    order =. /:(-counts),.palette
    'colors counts' record (<order{palette),<order{counts
)
write_lines =: 4 : 0
    ((LF join y),LF#~0<#y) 1!:2 <'output/',x
    i.0
)
write_reports =: 3 : 0
    image =. composite ''
    write_ppm image
    write_preview image
    commands =. 0$a:
    drawing =. state =. errors =. painted =. erased =. 0
    errorcounts =. (#ErrorNames)$0
    keywords =. empty_table ''
    for_box. Executions do.
        execution =. >box
        key =. 'keyword' get_key execution
        kind =. 'kind' get_key execution
        count =. #'pixels' get_key execution
        fields =. (<'cmd'),(<'sequence' get_key execution),(<'line'),(<'line' get_key execution),<key
        tally =. 0 0 0
        if. key has_key keywords do. tally =. key get_key keywords end.
        tally =. (1+0{tally) 0}tally
        if. kind-:'error' do.
            errors =. errors+1
            error =. 'error' get_key execution
            index =. ErrorNames i.<error
            errorcounts =. (1+index{errorcounts) index}errorcounts
            tally =. (1+1{tally) 1}tally
            fields =. fields,(<'error'),<error
        elseif. kind-:'state' do.
            state =. state+1
            fields =. fields,<'ok'
        else.
            drawing =. drawing+1
            if. key-:'ERASE' do. erased =. erased+count else. painted =. painted+count end.
            tally =. (count+2{tally) 2}tally
            fields =. fields,(<'pixels'),(<count),(<'box'),<box_text 'pixels' get_key execution
        end.
        keywords =. ((<key),<tally) put_key keywords
        commands =. commands,<text_line fields
    end.
    'commands.txt' write_lines commands
    alphas =. 0$a:
    for_box. Layers do. alphas =. alphas,<effective_alpha >box end.
    lines =. <'layers ',number #Layers
    for_index. i.#Layers do.
        layer =. index{::Layers
        pixels =. I.'painted' get_key layer
        visible =. 0<index{::alphas
        for_later. (index+1)+i.(#Layers)-(index+1) do.
            visible =. visible*.255>later{::alphas
        end.
        colors =. rank_colors pixels{'colors' get_key layer
        palette =. 'colors' get_key colors
        counts =. 'counts' get_key colors
        fields =. (<'layer'),(<index+1),(<'name' get_key layer),(<'opacity'),(<'opacity' get_key layer),(<'mode'),(<'mode' get_key layer),(<'commands'),(<'commands' get_key layer),(<'errors'),(<'errors' get_key layer),(<'pixels'),(<#pixels),(<'box'),(<box_text pixels),(<'visible'),(<+/visible),(<'colors'),<#palette
        lines =. lines,<text_line fields
        for_color. i.5<.#counts do.
            lines =. lines,<text_line (<'color'),(number&.><"0 color{palette),(<'pixels'),<color{counts
        end.
    end.
    'layers.txt' write_lines lines
    colors =. rank_colors image
    palette =. 'colors' get_key colors
    counts =. 'counts' get_key colors
    lines =. (<text_line (<'canvas'),(<Width),<Height),(<text_line (<'background'),number&.><"0 3{.Background),(<text_line (<'layers'),<#Layers),(<text_line (<'symbols'),<#Symbols),(<text_line (<'commands'),<#Executions),(<text_line (<'drawing'),<drawing),(<text_line (<'state'),<state),<text_line (<'errors'),<errors
    for_index. i.#ErrorNames do. lines =. lines,<text_line (<'error'),(index{ErrorNames),<index{errorcounts end.
    lines =. lines,(<text_line (<'painted'),<painted),(<text_line (<'erased'),<erased),<text_line (<'colors'),<#palette
    for_index. i.8<.#counts do. lines =. lines,<text_line (<'top'),(<index+1),(number&.><"0 index{palette),(<'pixels'),<index{counts end.
    for_namebox. /:~table_keys Symbols do.
        name =. >namebox
        index =. (table_keys Symbols)i.<name
        lines =. lines,<text_line (<'symbol'),(<name),(<'uses'),<index{Uses
    end.
    for_keybox. /:~table_keys keywords do.
        key =. >keybox
        tally =. key get_key keywords
        lines =. lines,<text_line (<'keyword'),(<key),(<'executed'),(<0{tally),(<'errors'),(<1{tally),(<'pixels'),<2{tally
    end.
    unused =. 0$a:
    kinds =. 'color';'pen';'brush';'symbol'
    tables =. (<Colors),(<Pens),(<Brushes),<Symbols
    used =. (<UsedColors),(<UsedPens),(<UsedBrushes),<(Uses>0)#table_keys Symbols
    for_index. i.4 do.
        names =. table_keys index{::tables
        names =. /:~names#~-.names e.index{::used
        for_namebox. names do. unused =. unused,<'unused ',(index{::kinds),' ',>namebox end.
    end.
    lines =. lines,(<text_line (<'unused'),<#unused),unused
    'summary.txt' write_lines lines
    lines =. 0$a:
    for_index. i.#Probes do.
        probe =. index{::Probes
        values =. 'values' get_key probe
        if. ('kind' get_key probe)-:'point' do.
            id =. (Width*1{values)+0{values
            stack =. 0$a:
            for_layerindex. i.#Layers do.
                if. (id{layerindex{::alphas)>0 do.
                    layer =. layerindex{::Layers
                    stack =. stack,<(number layerindex+1),':',number id{'lines' get_key layer
                end.
            end.
            listed =. 'none'
            if. #stack do. listed =. ' ' join stack end.
            fields =. (<'point'),(<index+1),(number&.><"0 values),(<'rgb'),(number&.><"0 id{image),(<'layers'),(<#stack),(<'stack'),<listed
            lines =. lines,<text_line fields
        else.
            pixels =. rect_pixels values
            count =. #pixels
            means =. (+/pixels{image) div count
            colors =. rank_colors pixels{image
            cover =. 0$0
            for_box. alphas do. cover =. cover,+/0<pixels{>box end.
            fields =. (<'area'),(<index+1),(number&.><"0 values),(<'pixels'),(<count),(<'mean'),(number&.><"0 means),(<'colors'),(<#'colors' get_key colors),(<'cover'),number&.><"0 cover
            lines =. lines,<text_line fields
        end.
    end.
    'probes.txt' write_lines lines
    i.0
)
main =: 3 : 0
    load_inputs ''
    for_index. i.#Layers do.
        CurrentLayer =: index
        Matrix =: 1 0 0 1 0 0
        Clip =: Screen
        Stack =: 0$a:
        execute_body 'body' get_key index{::Layers
    end.
    1!:5 <'output'
    write_reports ''
)
main ''
