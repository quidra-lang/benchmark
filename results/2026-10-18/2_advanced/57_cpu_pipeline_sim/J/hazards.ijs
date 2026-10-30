dependencies =: 3 : 0
    last =. 32$_1
    result =. 0$a:
    for_i. i.#y do.
        instruction =. i{y
        operands =. 0 2$0
        for_field. 3 4 do.
            register =. field{instruction
            if. register>0 do.
                operands =. operands,register,register{last
            end.
        end.
        result =. result,<operands
        destination =. 2{instruction
        if. destination>0 do.
            last =. i destination}last
        end.
    end.
    result
)
id_resolved =: 4 : 0
    kind =. 1{y
    ((kind=5)*.0>3{y)+.((kind e.4 5)*.'ID'-:x)
)
source_ready =: 4 : 0
    'instruction producer timing' =. y
    'name forwarding stage latency' =. x
    if. -.forwarding do.
        1+4{timing return.
    end.
    result =. (3+(2=1{producer)){timing
    result+stage id_resolved instruction
)
forwarding_path =: 4 : 0
    'instruction producer_time instruction_time' =. y
    'name forwarding stage latency' =. x
    if. (0=#producer_time)+.-.forwarding do.
        0 return.
    end.
    resolved =. stage id_resolved instruction
    use_cycle =. (2{instruction_time)-resolved
    if. (3{producer_time)=use_cycle do. 1 return. end.
    if. (-.resolved)*.(4{producer_time)=use_cycle do. 2 return. end.
    0
)
