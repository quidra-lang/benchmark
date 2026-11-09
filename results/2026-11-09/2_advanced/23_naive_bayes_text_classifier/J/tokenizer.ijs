tokenize_text =: 3 : 0
    text =. lower y
    extracted =. 0$a:
    current =. ''
    for_character. text do.
        if. character e.'abcdefghijklmnopqrstuvwxyz0123456789' do. current =. current,character
        elseif. #current do. extracted =. extracted,<current
            current =. '' end.
    end.
    if. #current do. extracted =. extracted,<current end.
    stopped =. short =. 0
    words =. bigrams =. 0$a:
    for_word. extracted do.
        if. word e.Stopwords do. stopped =. stopped+1
        elseif. 1=#>word do. short =. short+1
        else. words =. words,word end.
    end.
    for_index. i.0>.(#words)-1 do.
        bigrams =. bigrams,<(index{::words),'_',(index+1){::words
    end.
    (<#extracted),(<stopped),(<short),(<words),(<bigrams),<words,bigrams
)
token_terms =: 4 : 0
    if. x do. 5{::y else. 3{::y end.
)
