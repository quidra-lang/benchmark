dec =: 3 : 0
    'a b places' =. y
    if. b=0 do. '-' return. end.
    scale =. */places#10
    z =. ((2*a*scale)+b) div 2*b
    (number z div scale),'.',(-places){.(places#'0'),number scale|z
)
frac =: 3 : 0
    'a b' =. y
    if. b=0 do. '-' return. end.
    divisor =. a+.b
    (number a div divisor),'/',number b div divisor
)
fraction =: 4 : '(x:x)%x:y'
share_text =: 3 : 'frac _1 x:2 x:y'
percentile =: 4 : '((((x*#y)+99) div 100)-1){y'
histogram_lines =: 4 : 0
    first =. ({.y) div x
    last =. ({:y) div x
    bins =. first+i.1+last-first
    counts =. 0$0
    for_bin. bins do. counts =. counts,+/bin=y div x end.
    top =. >./counts
    lines =. 0$a:
    for_index. i.#bins do.
        low =. x*index{bins
        count =. index{counts
        text =. text_line (<'  ',range_text low,(low+x)-1),<count
        stars =. ((80*count)+top) div 2*top
        if. stars>0 do. text =. text,' ',stars#'*' end.
        lines =. lines,<text
    end.
    lines
)
