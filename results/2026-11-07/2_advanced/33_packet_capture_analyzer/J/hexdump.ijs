read_lines =: 3 : '<;._2 (1!:1 <y)'
hex_digits =: 3 : '(0<#y)*.*./y e.''0123456789abcdef'''
hex_value =: 3 : 0
    result =. 0x
    for_character. y do.
        digit =. '0123456789abcdefABCDEF'i.character
        if. digit>:16 do.
            digit =. digit-6
        end.
        result =. (16*result)+digit
    end.
    result
)
hexadecimal =: 4 : 0
    result =. ''
    value =. y
    while. (value>0)+.x>#result do.
        result =. ((16|value){'0123456789abcdef'),result
        value =. value intdiv 16
    end.
    if. 0=#result do.
        '0'
    else.
        result
    end.
)
new_fields =: 3 : '(<0$a:),<0$a:'
field_values =: 4 : 0
    index =. (0{::x)i.<y
    if. index=#0{::x do.
        0$a:
    else.
        index{::1{::x
    end.
)
field_value =: 4 : 0
    values =. x field_values y
    if. 0=#values do.
        _1
    else.
        0{::values
    end.
)
field_exists =: 4 : '(<y)e.0{::x'
field_put =: 4 : 0
    'name value' =. y
    names =. 0{::x
    values =. 1{::x
    index =. names i.<name
    atom =. ,<value
    if. index=#names do.
        names =. names,<name
        values =. values,<atom
    else.
        values =. (<atom)index}values
    end.
    (<names),<values
)
field_add =: 4 : 0
    'name value' =. y
    names =. 0{::x
    values =. 1{::x
    index =. names i.<name
    if. index=#names do.
        names =. names,<name
        values =. values,<,<value
    else.
        values =. (<(index{::values),<value)index}values
    end.
    (<names),<values
)
p_values =: 4 : '(6{::x)field_values y'
p_value =: 4 : '(6{::x)field_value y'
p_exists =: 4 : '(6{::x)field_exists y'
p_put =: 4 : '(<(6{::x)field_put y)6}x'
l_put =: 4 : '(<(0{::x)field_put y)0}x'
l_add =: 4 : '(<(0{::x)field_add y)0}x'
p_number =: 0&{::
p_time =: 1&{::
p_length =: 2&{::
p_data =: 3&{::
p_error =: 4&{::
p_layers =: 5&{::
p_fields =: 6&{::
p_remaining =: 7&{::
p_answers =: 8&{::
new_packet =: 3 : 0
    'number time length' =. y
    (<number),(<time),(<length),(<i.0),(<''),(<0$a:),(<new_fields 0),(<i.0),<0$a:
)
read_capture =: 3 : 0
    packets =. 0$a:
    line_number =. 0
    for_box. read_lines y do.
        line_number =. line_number+1
        line =. >box
        if. ((#line)>:7)*.'PACKET '-:7{.line do.
            header =. num&>}. ' 'split line
            packet =. new_packet header
            packets =. packets,<packet
            continue.
        end.
        if. 0=#line do.
            continue.
        end.
        index =. <:#packets
        packet =. index{::packets
        if. #p_error packet do.
            continue.
        end.
        valid =. (#line)>:8
        byte_tokens =. 0$a:
        if. valid do.
            valid =. ('  '-:4 5{line)*.hex_digits 4{.line
            if. valid do.
                byte_tokens =. ' 'split 6}.line
                valid =. (1<:#byte_tokens)*.16>:#byte_tokens
                for_token. byte_tokens do.
                    valid =. valid*.(2=#>token)*.hex_digits >token
                end.
            end.
        end.
        reason =. ''
        if. -.valid do.
            reason =. 'dump: bad line ',text line_number
        elseif. (hex_value 4{.line)~:#p_data packet do.
            reason =. 'dump: offset mismatch at line ',text line_number
        end.
        if. #reason do.
            packet =. (<reason)4}packet
        else.
            packet =. (<(p_data packet),hex_value&>byte_tokens)3}packet
        end.
        packets =. (<packet)index}packets
    end.
    for_index. i.#packets do.
        packet =. index{::packets
        if. (0=#p_error packet)*.(p_length packet)~:#p_data packet do.
            reason =. 'dump: length mismatch (header ',(text p_length packet),', data ',(text #p_data packet),')'
            packet =. (<reason)4}packet
            packets =. (<packet)index}packets
        end.
    end.
    packets
)
hex_dump =: 3 : 0
    lines =. 0$a:
    for_offset. 16*i.(((#y)+15)intdiv 16) do.
        piece =. (16<.(#y)-offset){.offset}.y
        pieces =. 0$a:
        characters =. ''
        for_byte. piece do.
            pieces =. pieces,<2 hexadecimal byte
            character =. '.'
            if. (byte>:32)*.byte<:126 do.
                character =. byte{a.
            end.
            characters =. characters,character
        end.
        hex =. ' 'join pieces
        lines =. lines,<(4 hexadecimal offset),'  ',hex,((47-#hex)#' '),'  |',characters,'|'
    end.
    lines
)
