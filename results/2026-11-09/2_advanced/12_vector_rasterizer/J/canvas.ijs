round_ratio =: 4 : 0
    if. y<0 do. x =. -x
        y =. -y end.
    ((2*x)+y) div 2*y
)
layer_record =: 3 : 0
    'name opacity mode body' =. y
    'name opacity mode body painted colors lines commands errors' record (<name),(<opacity),(<mode),(<body),(<PixelCount$0),(<(PixelCount,4)$0),(<PixelCount$0),(<0),<0
)
layer_get =: 3 : 'y get_key CurrentLayer{::Layers'
layer_set =: 4 : 0
    layer =. ((<x),<y) put_key CurrentLayer{::Layers
    Layers =: (<layer) CurrentLayer}Layers
    i.0
)
layer_add =: 4 : 'x layer_set y+layer_get x'
effective_alpha =: 3 : 0
    values =. (3{"1 'colors' get_key y)*'opacity' get_key y
    ('painted' get_key y)*values round_ratio 255
)
composite =: 3 : 0
    image =. (PixelCount,3)$3{.Background
    for_box. Layers do.
        layer =. >box
        ids =. I.'painted' get_key layer
        alpha =. ids{effective_alpha layer
        colors =. ids{'colors' get_key layer
        mode =. 'mode' get_key layer
        for_channel. i.3 do.
            source =. channel{"1 colors
            values =. channel{"1 image
            value =. ids{values
            if. mode-:'multiply' do. source =. (source*value) round_ratio 255
            elseif. mode-:'screen' do. source =. 255-((255-source)*(255-value)) round_ratio 255 end.
            result =. ((alpha*source)+(255-alpha)*value) round_ratio 255
            values =. result ids}values
            image =. |:values channel}|:image
        end.
    end.
    image
)
