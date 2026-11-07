read_lines =: 3 : '<;._2 (1!:1 <y)'
split_words =: 3 : '<;._1 '' '',y'
integer_value =: 3 : 'x:". ''_''(I.y=''-'')}y'
material_index =: 4 : 0
    for_j. i.#x do.
        if. y-:0{::j{::x do.
            j return.
        end.
    end.
    _1
)
read_scene =: 3 : 0
    eye =. forward =. right =. up =. background =. 3$0x
    view =. 2$0x
    ambient =. 0x
    fog =. i.0x
    materials =. 0$a:
    objects =. 0$a:
    lights =. 0$a:
    for_line. read_lines 'input/scene.txt' do.
        line =. >line
        if. 0=#line do.
            continue.
        end.
        if. '#'={.line do.
            continue.
        end.
        fields =. split_words line
        kind =. 0{::fields
        if. kind-:'material' do.
            values =. integer_value&>2}.fields
            materials =. materials,< (1{fields),(<values),(<i.0x),<0x
        elseif. kind-:'checker' do.
            index =. materials material_index 1{::fields
            values =. integer_value&>2}.fields
            material =. index{::materials
            material =. (<3{.values)2}material
            material =. (<3{values)3}material
            materials =. (<material)index}materials
        elseif. (<kind)e.;:'sphere plane box' do.
            geometry =. integer_value&>3}.fields
            if. kind-:'plane' do.
                geometry =. (3{.geometry),vnorm 3}.geometry
            end.
            index =. materials material_index 2{::fields
            objects =. objects,< (1{fields),(<kind),(<index),<geometry
        else.
            values =. integer_value&>}.fields
            if. (<kind)e.;:'point spot sun area' do.
                samples =. 1
                if. kind-:'sun' do.
                    values =. (vnorm -3{.values),3}.values
                elseif. kind-:'spot' do.
                    values =. (3{.values),(vnorm 3 4 5{values),6}.values
                elseif. kind-:'area' do.
                    samples =. *:9{values
                end.
                lights =. lights,<(<kind),(<values),<samples
            else.
                select. kind
                case. 'eye' do. eye =. values
                case. 'forward' do. forward =. values
                case. 'right' do. right =. values
                case. 'up' do. up =. values
                case. 'view' do. view =. values
                case. 'background' do. background =. values
                case. 'ambient' do. ambient =. {.values
                case. 'fog' do. fog =. values
                end.
            end.
        end.
    end.
    (<eye),(<forward),(<right),(<up),(<view),(<background),(<ambient),(<fog),(<materials),(<objects),<lights
)
