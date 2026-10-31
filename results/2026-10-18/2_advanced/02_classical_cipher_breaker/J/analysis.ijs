letter_counts =: 3 : '+/y =/ Alphabet'
ioc =: 3 : 0
    counts =. x:letter_counts y
    sum =. +/counts*counts-1
    (100000x*sum) div (#y)*(#y)-1
)
columns =: 4 : 0
    result =. 0$a:
    for_column. i.x do.
        result =. result,<(column=x|i.#y)#y
    end.
    result
)
column_indices =: 4 : 'ioc&>x columns y'
repeated_trigrams =: 3 : 0
    trigrams =. 0$a:
    for_index. i.0>.(#y)-2 do.
        trigrams =. trigrams,<3{.index}.y
    end.
    repeats =. 0$a:
    for_box. /:~ ~.trigrams do.
        trigram =. >box
        positions =. >:I.(<trigram)=trigrams
        if. 2>#positions do. continue. end.
        gaps =. (}.positions)-}:positions
        divisor =. 0
        for_gap. gaps do. divisor =. divisor+.gap end.
        repeats =. repeats,<(<trigram),(<positions),(<gaps),<divisor
    end.
    repeats
)
percentage =: 4 : 0
    tenths =. ((2000*x)+y) div 2*y
    (number tenths div 10),'.',number 10|tenths
)
pair_counts =: 4 : 0
    counts =. empty_table ''
    for_index. i.0>.(#y)-1 do.
        if. 0~:x|index do. continue. end.
        pair =. 2{.index}.y
        count =. 0
        if. pair has_key counts do. count =. pair get_key counts end.
        counts =. ((<pair),<count+1) put_key counts
    end.
    counts
)
top_counts =: 3 : 0
    if. 0=#y do. y return. end.
    counts =. >1{"1 y
    codes =. a.i.>table_keys y
    order =. /:(-counts),.codes
    (10<.#y){.order{y
)
