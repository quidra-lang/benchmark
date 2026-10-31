LF =: 10{a.
Alphabet =: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
Lowercase =: 'abcdefghijklmnopqrstuvwxyz'
Digits =: '0123456789'
AffineMultipliers =: 1 3 5 7 9 11 15 17 19 21 23 25
is_letter =: 3 : 'y e.Alphabet,Lowercase'
uppercase =: 3 : 0
    text =. ,y
    positions =. I.text e.Lowercase
    letters =. (Lowercase i.positions{text){Alphabet
    letters positions}text
)
letter_values =: 3 : 'Alphabet i.uppercase y'
letter_string =: 3 : 'uppercase (is_letter y)#y'
read_weights =: 3 : 0
    source =. read_lines y
    Monograms =: num&>' ' split 1{::source
    Bigrams =: 0 26$0
    for_line. 3}.source do.
        Bigrams =: Bigrams,num&>' ' split >line
    end.
    i.0
)
monogram_fitness =: 3 : '+/(Alphabet i.y){Monograms'
bigram_fitness =: 3 : 0
    if. 2>#y do. 0 return. end.
    values =. Alphabet i.y
    +/((26*}:values)+}.values){,Bigrams
)
