valid_word =: 3 : '((3<:#y)*.(#y)<:15)*.*./y e.Uppercase'
valid_integer =: 4 : 0
    'low high' =. x
    if. (0=#y)+.(#y)>#number high do. 0 return. end.
    if. ('0'={.y)+.-.*./y e.Digits do. 0 return. end.
    value =. num y
    (low<:value)*.value<:high
)
word_line_error =: 3 : 0
    if. 1~:+/y=' ' do. 'bad format' return. end.
    'word score' =. ' ' split y
    if. -.valid_word word do. 'bad word' return. end.
    if. -.1 100 valid_integer score do. 'bad score' return. end.
    ''
)
clue_line_error =: 3 : 0
    if. 1~:+/y='|' do. 'bad format' return. end.
    'word clue' =. '|' split y
    if. -.valid_word word do. 'bad word' return. end.
    if. (0=#clue)+.(#clue)>60 do. 'bad clue' return. end.
    if. (' '={.clue)+.' '={:clue do. 'bad clue' return. end.
    ''
)
matches =: 4 : '*./(y=''.'')+.x=y'
build_word_index =: 3 : 0
    ByLength =: 16$<0$0
    ByLetter =: 16 15 26$<0$0
    for_word. i.#WordNames do.
        text =. word{::WordNames
        length =. #text
        ByLength =: (<(length{::ByLength),word)length}ByLength
        for_position. i.length do.
            index =. <length,position,Uppercase i.position{text
            ByLetter =: (<(index{::ByLetter),word)index}ByLetter
        end.
    end.
    i.0
)
candidates =: 4 : 0
    pattern =. x
    'minimum used' =. y
    length =. #pattern
    pool =. length{::ByLength
    for_position. i.length do.
        mark =. position{pattern
        if. mark~:'.' do.
            bucket =. (<length,position,Uppercase i.mark){::ByLetter
            if. (#bucket)<#pool do. pool =. bucket end.
        end.
    end.
    result =. 0$0
    for_word. pool do.
        if. (word{WordScores)<minimum do. break. end.
        if. -.word e.used do.
            if. (word{::WordNames)matches pattern do. result =. result,word end.
        end.
    end.
    result
)
