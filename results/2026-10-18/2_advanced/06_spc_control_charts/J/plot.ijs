place =: 4 : 0
    'position symbol' =. y
    symbol (0>.60<.position)}x
)
framed_band =: 3 : 0
    band =. 61#'.'
    band =. ':' 0 60}band
    band place (<y),<'|'
)
limits_band =: 4 : 0
    'value signalled' =. y
    lcl =. 'lcl' get_key x
    span =. ('ucl' get_key x)-lcl
    center =. <.!.0 (60.0*(('cl' get_key x)-lcl)%span)+0.5
    position =. <.!.0 (60.0*(value-lcl)%span)+0.5
    symbol =. signalled{::'o';'*'
    (framed_band center) place (<position),<symbol
)
cusum_band =: 3 : 0
    'upper lower threshold uppersignal lowersignal' =. y
    band =. framed_band 30
    if. lower>!.0 0 do.
        offset =. 30<.<.!.0 (30.0*lower%threshold)+0.5
        symbol =. lowersignal{::'-';'*'
        band =. band place (<30-offset),<symbol
    end.
    if. upper>!.0 0 do.
        offset =. 30<.<.!.0 (30.0*upper%threshold)+0.5
        symbol =. uppersignal{::'+';'*'
        band =. band place (<30+offset),<symbol
    end.
    band
)
width_band =: 3 : 0
    'scale width value center signalled' =. y
    band =. 61#'.'
    edge =. 30<.<.!.0 (30.0*width%scale)+0.5
    band =. band place (<30),<'|'
    band =. band place (<30-edge),<':'
    band =. band place (<30+edge),<':'
    position =. 30+<.!.0 (30.0*(value-center)%scale)+0.5
    symbol =. signalled{::'o';'*'
    band place (<position),<symbol
)
standard_band =: 4 : 0
    position =. 30+<.!.0 (10.0*x)+0.5
    symbol =. y{::'*';'o'
    (framed_band 30) place (<position),<symbol
)
