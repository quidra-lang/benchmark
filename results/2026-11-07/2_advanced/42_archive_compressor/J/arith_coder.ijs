arith_reset =: 3 : 0
    ArithFrequencies =: 256 257$1x
    ArithTotals =: 256$257x
    ArithRescales =: 256$0
    ArithUsed =: 256$0
    0
)
arith_interval =: 3 : 0
    'context symbol' =. y
    row =. context{ArithFrequencies
    (+/symbol{.row),symbol{row
)
arith_locate =: 3 : 0
    'context value' =. y
    row =. context{ArithFrequencies
    symbol =. 0
    cumulative =. 0x
    while. value>:cumulative+symbol{row do.
        cumulative =. cumulative+symbol{row
        symbol =. symbol+1
    end.
    symbol,cumulative,symbol{row
)
arith_update =: 3 : 0
    'context symbol' =. y
    ArithFrequencies =: (32+(<context,symbol){ArithFrequencies)(<context,symbol)}ArithFrequencies
    ArithTotals =: (32+context{ArithTotals)context}ArithTotals
    if. 8192<:context{ArithTotals do.
        row =. ((context{ArithFrequencies)+1)intdiv 2
        ArithFrequencies =: row context}ArithFrequencies
        ArithTotals =: (+/row)context}ArithTotals
        ArithRescales =: (1+context{ArithRescales)context}ArithRescales
    end.
    0
)
arith_emit =: 3 : 0
    ArithWriter =: ArithWriter write_bits y,1
    for_index. i.ArithFollow do.
        ArithWriter =: ArithWriter write_bits (1-y),1
    end.
    ArithFollow =: 0
    0
)
arith_encode =: 3 : 0
    arith_reset 0
    ArithWriter =: 0$0
    ArithFollow =: 0
    low =. 0x
    high =. 65535x
    context =. 10
    for_symbol. (x:y),256 do.
        ArithUsed =: 1 context}ArithUsed
        'cumulative frequency' =. arith_interval context,symbol
        span =. (high-low)+1
        old_low =. low
        high =. (old_low+((span*(cumulative+frequency))intdiv context{ArithTotals))-1
        low =. old_low+(span*cumulative)intdiv context{ArithTotals
        while. 1 do.
            if. high<32768 do.
                arith_emit 0
            elseif. low>:32768 do.
                arith_emit 1
                low =. low-32768
                high =. high-32768
            elseif. (low>:16384)*.high<49152 do.
                ArithFollow =: ArithFollow+1
                low =. low-16384
                high =. high-16384
            else.
                break.
            end.
            low =. 2*low
            high =. (2*high)+1
        end.
        if. symbol~:256 do.
            arith_update context,symbol
            context =. symbol
        end.
    end.
    ArithFollow =: ArithFollow+1
    arith_emit low>:16384
    stats =. (#ArithWriter),(+/ArithUsed),+/ArithRescales
    (<finish_bits ArithWriter),<stats
)
arith_decode =: 3 : 0
    'payload original' =. y
    arith_reset 0
    reader =. new_reader (<payload),<1
    output =. i.0x
    low =. 0x
    high =. 65535x
    'reader value' =. reader read_bits 16,0
    context =. 10
    while. 1 do.
        span =. (high-low)+1
        quantile =. ((((value-low)+1)*(context{ArithTotals))-1)intdiv span
        'symbol cumulative frequency' =. arith_locate context,quantile
        old_low =. low
        high =. (old_low+((span*(cumulative+frequency))intdiv context{ArithTotals))-1
        low =. old_low+(span*cumulative)intdiv context{ArithTotals
        while. 1 do.
            if. high>:32768 do.
                if. low>:32768 do.
                    low =. low-32768
                    high =. high-32768
                    value =. value-32768
                elseif. (low>:16384)*.high<49152 do.
                    low =. low-16384
                    high =. high-16384
                    value =. value-16384
                else.
                    break.
                end.
            end.
            low =. 2*low
            high =. (2*high)+1
            'reader next_bit' =. reader read_bits 1,0
            value =. (2*value)+next_bit
        end.
        if. symbol=256 do.
            if. (#output)<original do.
                'early_end'decode_failure #output return.
            end.
            decode_ok output return.
        end.
        if. (#output)=original do.
            'overrun'decode_failure #output return.
        end.
        output =. output,symbol
        arith_update context,symbol
        context =. symbol
    end.
)
