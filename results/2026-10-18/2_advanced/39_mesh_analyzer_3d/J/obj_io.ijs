read_lines =: 3 : '<;._2 (1!:1 <y)'
words =: 3 : '<;._1 '' '',y'
num =: 3 : 0
    if. '-'={.y do.
        -x:0".}.y
    else.
        x:0".y
    end.
)
text =: 3 : 0
    value =. ":y
    '-'(I.value='_')}value
)
join =: 4 : 0
    result =. ''
    for_index. i.#y do.
        if. index do.
            result =. result,x
        end.
        result =. result,index{::y
    end.
    result
)
listing =: 3 : 0
    if. #y do.
        ' 'join text&.>y
    else.
        '-'
    end.
)
integer_word =: 3 : 0
    digits =. y
    if. #digits do.
        if. '-'={.digits do.
            digits =. }.digits
        end.
    end.
    (0<#digits)*.*./digits e.'0123456789'
)
read_obj =: 3 : 0
    lines =. read_lines 'input/model.obj'
    vertices =. 0 3$0x
    polygons =. 0$a:
    polygon_lines =. i.0
    polygon_groups =. 0$a:
    errors =. 0$a:
    ignored =. 0
    group =. 'default'
    for_index. i.#lines do.
        line =. index{::lines
        if. 0=#line do.
            continue.
        end.
        if. '#'={.line do.
            continue.
        end.
        tokens =. words line
        keyword =. 0{::tokens
        args =. }.tokens
        reason =. ''
        if. (,keyword)-:,'v' do.
            valid =. (3=#args)*.*./integer_word&>args
            if. valid do.
                vertices =. vertices,num&>args
            else.
                reason =. 'bad_vertex'
            end.
        elseif. (,keyword)-:,'f' do.
            if. 3>#args do.
                reason =. 'short_face'
            else.
                resolved =. i.0
                for_box. args do.
                    reference =. >box
                    part =. (reference i.'/'){.reference
                    if. -.integer_word part do.
                        reason =. 'bad_index'
                        break.
                    end.
                    number =. num part
                    if. number=0 do.
                        reason =. 'bad_index'
                        break.
                    end.
                    if. number<0 do.
                        number =. (1+#vertices)+number
                    end.
                    if. (number<1)+.number>#vertices do.
                        reason =. 'out_of_range'
                        break.
                    end.
                    resolved =. resolved,number
                end.
                if. 0=#reason do.
                    polygons =. polygons,<resolved
                    polygon_lines =. polygon_lines,index+1
                    polygon_groups =. polygon_groups,<group
                end.
            end.
        elseif. (,keyword)-:,'g' do.
            group =. 'default'
            if. #args do.
                group =. 0{::args
            end.
        elseif. (<keyword)e.;:'vt vn s o usemtl mtllib' do.
            ignored =. ignored+1
        else.
            reason =. 'unknown_keyword'
        end.
        if. #reason do.
            errors =. errors,<'line ',(text index+1),' ',reason
        end.
    end.
    (<#lines),(<vertices),(<polygons),(<polygon_lines),(<polygon_groups),(<errors),<ignored
)
repaired_obj =: 3 : 0
    'points faces groups' =. y
    lines =. <'# vertices ',(text #points),' faces ',text #faces
    for_point. points do.
        lines =. lines,<'v ',listing point
    end.
    previous =. ''
    for_index. i.#faces do.
        group =. index{::groups
        if. -.group-:previous do.
            lines =. lines,<'g ',group
            previous =. group
        end.
        lines =. lines,<'f ',listing 3{.index{faces
    end.
    lines
)
