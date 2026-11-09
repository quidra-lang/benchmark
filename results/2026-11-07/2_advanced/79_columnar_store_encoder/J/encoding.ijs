Methods =: ;:'PLAIN DICTIONARY RLE DELTA_BINARY_PACKED DELTA_LENGTH_BYTE_ARRAY'
Candidates =: ( <0 1 3),(<0 1 4),(<0 2),<0 1 3
delta_encode =: 3 : 0
    first =. 0
    if. #y do.
        first =. {.y
    end.
    bytes =. (uleb 128),(uleb 4),(uleb #y),zigzag first
    deltas =. (}.y)-}:y
    start =. 0
    while. start<#deltas do.
        block =. (128<.(#deltas)-start){.start}.deltas
        minimum =. <./block
        bytes =. bytes,zigzag minimum
        miniblocks =. 0$a:
        widths =. i.0
        for_t. i.4 do.
            part =. (32<.0>.(#block)-32*t){.(32*t)}.block
            part =. part-minimum
            width =. 0
            if. #part do.
                width =. bit_width >./part
            end.
            miniblocks =. miniblocks,<part
            widths =. widths,width
        end.
        bytes =. bytes,widths
        for_t. i.4 do.
            part =. t{::miniblocks
            if. #part do.
                part =. part,(32-#part)$0
                bytes =. bytes,(t{widths)pack part
            end.
        end.
        start =. start+128
    end.
    bytes
)
delta_decode =: 3 : 0
    block_size =. read_uleb ''
    miniblock_count =. read_uleb ''
    count =. read_uleb ''
    first =. read_zigzag ''
    values =. i.0
    if. count do.
        values =. ,first
    end.
    miniblock_size =. block_size intdiv miniblock_count
    while. count>#values do.
        minimum =. read_zigzag ''
        widths =. read_bytes miniblock_count
        for_width. widths do.
            if. count=#values do.
                break.
            end.
            differences =. width unpack miniblock_size
            differences =. (miniblock_size<.count-#values){.differences
            for_difference. differences do.
                values =. values,({:values)+minimum+difference
            end.
        end.
    end.
    values
)
encode_values =: 4 : 0
    'kind method dictionary' =. x
    values =. y
    bytes =. i.0
    select. method
    case. 0 do.
        if. kind e.0 3 do.
            for_value. values do.
                bytes =. bytes,write_integer >value
            end.
            bytes
        elseif. kind=1 do.
            for_value. values do.
                value =. >value
                bytes =. bytes,(write_integer #value),a.i.value
            end.
            bytes
        else.
            integers =. i.0
            if. #values do.
                integers =. >values
            end.
            integers =. integers,(8|-#integers)$0
            1 pack integers
        end.
    case. 1 do.
        width =. bit_width (#dictionary)-1
        ranks =. dictionary i.values
        width,width hybrid_encode ranks
    case. 2 do.
        bytes =. 1 hybrid_encode >values
        (write_integer #bytes),bytes
    case. 3 do.
        integers =. i.0
        if. #values do.
            integers =. >values
        end.
        delta_encode integers
    case. 4 do.
        bytes =. delta_encode #&>values
        for_value. values do.
            bytes =. bytes,a.i.>value
        end.
        bytes
    end.
)
decode_values =: 4 : 0
    'kind method count' =. x
    dictionary =. y
    select. method
    case. 0 do.
        values =. 0$a:
        if. kind e.0 3 do.
            for_i. i.count do.
                values =. values,<read_integer 1
            end.
        elseif. kind=1 do.
            for_i. i.count do.
                length =. read_integer 0
                values =. values,<a.{~read_bytes length
            end.
        else.
            values =. <"0 count{.1 unpack 8*((count+7)intdiv 8)
        end.
        values
    case. 1 do.
        width =. read_byte ''
        (width hybrid_decode count){dictionary
    case. 2 do.
        length =. read_integer 0
        finish =. ReadPosition+length
        values =. <"0 (1 hybrid_decode count)
        ReadPosition =: finish
        values
    case. 3 do.
        <"0 delta_decode ''
    case. 4 do.
        lengths =. delta_decode ''
        values =. 0$a:
        for_length. lengths do.
            values =. values,<a.{~read_bytes length
        end.
        values
    end.
)
encode_statistics =: 4 : 0
    if. 0=#y do.
        ,0 return.
    end.
    bytes =. ,1
    for_value. y do.
        value =. >value
        if. x e.0 3 do.
            bytes =. bytes,zigzag value
        elseif. x=1 do.
            bytes =. bytes,(uleb #value),a.i.value
        else.
            bytes =. bytes,value
        end.
    end.
    bytes
)
decode_statistics =: 3 : 0
    if. 0=read_byte '' do.
        0$a: return.
    end.
    values =. 0$a:
    for_i. i.2 do.
        if. y e.0 3 do.
            value =. read_zigzag ''
        elseif. y=1 do.
            length =. read_uleb ''
            value =. a.{~read_bytes length
        else.
            value =. read_byte ''
        end.
        values =. values,<value
    end.
    values
)
