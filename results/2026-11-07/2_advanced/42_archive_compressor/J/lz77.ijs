lz77_tokenize =: 3 : 0
    'data offset_bits length_bits' =. y
    data =. x:data
    window =. 2x^offset_bits
    lookahead =. (2x^length_bits)+2
    position =. 0
    tokens =. 0 3$0x
    prefixes =. 0 3$0x
    if. 3<:#data do.
        prefixes =. 3]\data
    end.
    while. position<#data do.
        distance =. 0
        longest =. 0
        limit =. lookahead<.(#data)-position
        if. limit>:3 do.
            first =. 0>.position-window
            starts =. first+i.position-first
            current =. position{prefixes
            candidates =. starts#~current-:"1 starts{prefixes
            for_start. |.candidates do.
                candidate_distance =. position-start
                length =. 3
                while. length<limit do.
                    if. ((position+length){data)~:(position+length-candidate_distance){data do.
                        break.
                    end.
                    length =. length+1
                end.
                if. length>longest do.
                    distance =. candidate_distance
                    longest =. length
                end.
                if. longest=limit do.
                    break.
                end.
            end.
        end.
        consumed =. 1
        if. longest>:3 do.
            tokens =. tokens,_1,distance,longest
            consumed =. longest
        else.
            tokens =. tokens,(position{data),0 0
        end.
        position =. position+consumed
    end.
    tokens
)
copy_match =: 3 : 0
    'output distance length original' =. y
    if. distance>#output do.
        'bad_offset'decode_failure #output return.
    end.
    if. ((#output)+length)>original do.
        'overrun'decode_failure #output return.
    end.
    for_index. i.length do.
        output =. output,((#output)-distance){output
    end.
    decode_ok output
)
