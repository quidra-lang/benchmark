initial_dictionary =: 3 : '<"1 ,.x:i.256'
emit_lzw =: 3 : 0
    'code length' =. y
    width =. 12<.bits 258+LzwSinceClear
    LzwWriter =: LzwWriter write_bits code,width
    LzwStats =: (1+0{LzwStats)0}LzwStats
    LzwStats =: (1+(width-7){LzwStats)(width-7)}LzwStats
    LzwStats =: ((6{LzwStats)>.length)6}LzwStats
    if. code=256 do.
        LzwStats =: (1+1{LzwStats)1}LzwStats
        LzwSinceClear =: 0
    else.
        LzwSinceClear =: LzwSinceClear+1
    end.
    0
)
lzw_encode =: 3 : 0
    data =. x:y
    dictionary =. (initial_dictionary 0),(<i.0x),<i.0x
    next_code =. 258
    LzwSinceClear =: 0
    LzwWriter =: 0$0
    LzwStats =: 7$0
    emit_lzw 256,0
    sequence =. i.0x
    for_value. data do.
        extended =. sequence,value
        index =. dictionary i.<extended
        if. index<#dictionary do.
            sequence =. extended
        else.
            emit_lzw (dictionary i.<sequence),#sequence
            dictionary =. dictionary,<extended
            next_code =. next_code+1
            if. next_code=4096 do.
                emit_lzw 256,0
                dictionary =. (initial_dictionary 0),(<i.0x),<i.0x
                next_code =. 258
            end.
            sequence =. ,value
        end.
    end.
    if. #sequence do.
        emit_lzw (dictionary i.<sequence),#sequence
    end.
    emit_lzw 257,0
    (<finish_bits LzwWriter),<LzwStats
)
lzw_decode =: 3 : 0
    'payload original' =. y
    reader =. new_reader (<payload),<0
    dictionary =. (initial_dictionary 0),(<i.0x),<i.0x
    previous =. _1
    since_clear =. 0
    output =. i.0x
    while. 1 do.
        count =. since_clear
        width =. 12<.bits 258+count
        'reader code' =. reader read_bits width,#output
        if. reader_failed reader do.
            reader_failure reader return.
        end.
        if. code=256 do.
            dictionary =. (initial_dictionary 0),(<i.0x),<i.0x
            previous =. _1
            since_clear =. 0
            continue.
        end.
        since_clear =. since_clear+1
        if. code=257 do.
            if. (#output)<original do.
                'early_end'decode_failure #output return.
            end.
            decode_ok output return.
        end.
        if. count=3838 do.
            'bad_code'decode_failure #output return.
        end.
        next_code =. #dictionary
        if. previous<0 do.
            if. code>:256 do.
                'bad_code'decode_failure #output return.
            end.
            sequence =. code{::dictionary
        elseif. code<next_code do.
            sequence =. code{::dictionary
        elseif. code=next_code do.
            preceding =. previous{::dictionary
            sequence =. preceding,{.preceding
        else.
            'bad_code'decode_failure #output return.
        end.
        if. ((#output)+#sequence)>original do.
            'overrun'decode_failure #output return.
        end.
        output =. output,sequence
        if. previous>:0 do.
            dictionary =. dictionary,<((previous{::dictionary),{.sequence)
        end.
        previous =. code
    end.
)
