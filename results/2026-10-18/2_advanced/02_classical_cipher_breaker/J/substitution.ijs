affine_inverse =: 3 : 0
    for_candidate. >:i.25 do.
        if. 1=26|y*candidate do. candidate return. end.
    end.
    0
)
substitute =: 4 : 0
    'cipher key decrypt' =. x
    multiplier =. 1
    offset =. 0
    if. cipher-:'caesar' do. offset =. num key
    elseif. cipher-:'affine' do.
        'multiplier offset' =. num&>',' split key
        if. decrypt do. multiplier =. affine_inverse multiplier end.
    end.
    text =. y
    plaintext =. 0$0
    for_index. i.#text do.
        character =. index{text
        if. -.is_letter character do. continue. end.
        value =. {.letter_values character
        if. (<cipher)e.;:'caesar affine' do.
            if. decrypt do. result =. multiplier*value-offset
            else. result =. offset+multiplier*value end.
        else.
            position =. #plaintext
            if. cipher-:'vigenere' do.
                shift =. {.letter_values ((#key)|position){key
            elseif. position<#key do.
                shift =. {.letter_values position{key
            else. shift =. (position-#key){plaintext end.
            if. decrypt do. result =. value-shift else. result =. value+shift end.
        end.
        result =. 26|result
        if. decrypt do. plaintext =. plaintext,result
        else. plaintext =. plaintext,value end.
        if. character e.Lowercase do. replacement =. result{Lowercase
        else. replacement =. result{Alphabet end.
        text =. replacement index}text
    end.
    text
)
