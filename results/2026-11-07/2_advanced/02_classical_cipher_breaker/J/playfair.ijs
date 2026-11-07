SquareLetters =: 'ABCDEFGHIKLMNOPQRSTUVWXYZ'
replace_j =: 3 : '''I'' (I.y=''J'')}y'
playfair_square =: 3 : '~.y,SquareLetters'
playfair_plaintext =: 3 : 0
    text =. replace_j y
    prepared =. ''
    index =. 0
    while. index<#text do.
        first =. index{text
        index =. index+1
        second =. 'X'
        if. first='X' do. second =. 'Q' end.
        if. index<#text do.
            if. first~:index{text do.
                second =. index{text
                index =. index+1
            end.
        end.
        prepared =. prepared,first,second
    end.
    prepared
)
valid_playfair =: 3 : 0
    if. 2|#y do. 0 return. end.
    text =. replace_j y
    for_index. 2*i.(#text) div 2 do.
        if. (index{text)=(index+1){text do. 0 return. end.
    end.
    1
)
playfair =: 4 : 0
    'key decrypt' =. x
    square =. playfair_square key
    if. decrypt do. text =. replace_j y else. text =. playfair_plaintext y end.
    step =. 1+3*decrypt
    result =. ''
    for_index. 2*i.(#text) div 2 do.
        first =. square i.index{text
        second =. square i.(index+1){text
        rowa =. first div 5
        rowb =. second div 5
        cola =. 5|first
        colb =. 5|second
        if. rowa=rowb do.
            cola =. 5|cola+step
            colb =. 5|colb+step
        elseif. cola=colb do.
            rowa =. 5|rowa+step
            rowb =. 5|rowb+step
        else.
            old =. cola
            cola =. colb
            colb =. old
        end.
        result =. result,((cola+5*rowa){square),(colb+5*rowb){square
    end.
    result
)
