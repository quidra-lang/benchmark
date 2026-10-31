integer_sqrt =: 3 : 0
    low =. 0
    high =. 1
    while. (high*high)<:y do. high =. high*2 end.
    while. (high-low)>1 do.
        middle =. (low+high) div 2
        if. (middle*middle)<:y do. low =. middle else. high =. middle end.
    end.
    low
)
energy =: 3 : '+/y*y'
rms =: 3 : 'integer_sqrt (energy y) div #y'
zero_crossings =: 3 : '+/((}:y)<0)~:(}.y)<0'
count_clipped =: 3 : '+/(y=_32768)+.y=32767'
crest_fraction =: 3 : 0
    denominator =. energy y
    if. denominator=0 do. 'none' return. end.
    p =. peak y
    numerator =. (p*p)*#y
    divisor =. numerator+.denominator
    (number numerator div divisor),'/',number denominator div divisor
)
autocorrelation =: 4 : '+/(((#y)-x){.y)*(x}.y)'
pitch_lag =: 3 : 0
    'samples low high' =. y
    best =. low
    value =. low autocorrelation samples
    for_lag. (low+1)+i.high-low do.
        candidate =. lag autocorrelation samples
        if. candidate>value do. best =. lag
            value =. candidate end.
    end.
    if. value>0 do. best else. _1 end.
)
