reader_begin =: 3 : 0
    ReadData =: y
    ReadPosition =: 0
)
read_bytes =: 3 : 0
    result =. y{.ReadPosition}.ReadData
    ReadPosition =: ReadPosition+y
    result
)
read_byte =: 3 : '{.read_bytes 1'
read_uleb =: 3 : 0
    value =. 0
    factor =. 1
    while. 1 do.
        byte =. read_byte ''
        value =. value+factor*128|byte
        if. byte<128 do.
            value return.
        end.
        factor =. factor*128
    end.
)
read_zigzag =: 3 : 0
    value =. read_uleb ''
    if. 2|value do.
        -(value+1)intdiv 2
    else.
        value intdiv 2
    end.
)
read_integer =: 3 : 0
    value =. 256#.|.read_bytes 4
    if. y*.value>:2147483648 do.
        value =. value-4294967296
    end.
    value
)
uleb =: 3 : 0
    bytes =. i.0
    value =. y
    while. value>:128 do.
        bytes =. bytes,128+128|value
        value =. value intdiv 128
    end.
    bytes,value
)
zigzag =: 3 : 0
    if. y<0 do.
        uleb _1-2*y
    else.
        uleb 2*y
    end.
)
write_integer =: 3 : '|.(4#256)#:4294967296|y'
pack =: 4 : 0
    if. (x=0)+.0=#y do.
        i.0 return.
    end.
    bits =. ,|."1 (x#2)#:y
    #.|."1 (((#bits)intdiv 8),8)$bits
)
unpack =: 4 : 0
    if. x=0 do.
        y$0 return.
    end.
    bytes =. read_bytes ((x*y)+7)intdiv 8
    bits =. ,|."1 (8#2)#:bytes
    #.|."1 (y,x)$(x*y){.bits
)
adler32 =: 3 : 0
    first =. 1
    second =. 0
    for_byte. y do.
        first =. 65521|first+byte
        second =. 65521|second+first
    end.
    first+65536*second
)
bit_width =: 3 : 0
    if. y=0 do.
        0
    else.
        ##:y
    end.
)
hybrid_encode =: 4 : 0
    width =. x
    values =. y
    count =. #values
    runs =. count$1
    for_i. |.i.0>.count-1 do.
        if. (i{values)=(i+1){values do.
            runs =. (1+(i+1){runs)i}runs
        end.
    end.
    bytes =. i.0
    index =. 0
    while. index<count do.
        run =. index{runs
        if. run>:8 do.
            size =. (width+7)intdiv 8
            bytes =. bytes,(uleb 2*run),|.(size#256)#:index{values
            index =. index+run
        else.
            finish =. index
            groups =. 0
            while. 1 do.
                finish =. finish+8
                groups =. groups+1
                if. (finish>:count)+.groups=63 do.
                    break.
                end.
                if. 8<:finish{runs do.
                    break.
                end.
            end.
            block =. ((finish<.count)-index){.index}.values
            block =. block,((finish-index)-#block)$0
            bytes =. bytes,(uleb 1+2*groups),width pack block
            index =. finish
        end.
    end.
    bytes
)
hybrid_decode =: 4 : 0
    values =. i.0
    while. y>#values do.
        header =. read_uleb ''
        if. 0=2|header do.
            value =. 256#.|.read_bytes (x+7)intdiv 8
            values =. values,(header intdiv 2)$value
        else.
            groups =. (header-1)intdiv 2
            values =. values,x unpack 8*groups
        end.
    end.
    y{.values
)
