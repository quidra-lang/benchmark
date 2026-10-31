intdiv =: 4 : '<.(x: x)%x: y'
bits =: 3 : 0
    count =. 0
    value =. y
    while. value>0 do.
        count =. count+1
        value =. value intdiv 2
    end.
    count
)
write_bits =: 4 : 0
    'value width' =. y
    x,0~:(width#2)#:value
)
finish_bits =: 3 : 0
    if. 0=#y do.
        i.0x return.
    end.
    padded =. y,((8|8-8|#y)#0)
    2#."1 (_8]\padded)
)
new_reader =: 3 : 0
    'payload zero_fill' =. y
    (<payload),(<0),(<zero_fill),(<''),<0
)
reader_failed =: 3 : '0<#3{::y'
read_bits =: 4 : 0
    'payload position zero_fill problem error_position' =. x
    'width output_position' =. y
    if. #problem do.
        (<x),<0 return.
    end.
    limit =. 8*#payload
    if. (-.zero_fill)*.(position+width)>limit do.
        reader =. (<payload),(<position),(<zero_fill),(<'end_of_data'),<output_position
        (<reader),<0 return.
    end.
    value =. 0x
    for_index. i.width do.
        value =. value*2
        if. position<limit do.
            byte =. (position intdiv 8){payload
            shift =. 7-8|position
            value =. value+2|byte intdiv 2x^shift
        end.
        position =. position+1
    end.
    reader =. (<payload),(<position),(<zero_fill),(<problem),<error_position
    (<reader),<value
)
decode_ok =: 3 : 0
    (<y),(<''),<0
)
decode_failure =: 4 : '(<i.0x),(<x),<y'
reader_failure =: 3 : '(3{::y)decode_failure 4{::y'
decoded_data =: 0&{::
decoded_kind =: 1&{::
decoded_position =: 2&{::
decoded_failed =: 3 : '0<#decoded_kind y'
