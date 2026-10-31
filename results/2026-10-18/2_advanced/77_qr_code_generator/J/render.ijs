symbol_lines =: 4 : '<@(''.#''&{~)"1 (x,x)$y'
pbm_lines =: 4 : 0
    'n quiet scale' =. x
    width =. scale*n+2*quiet
    lines =. (<'P1'),<(integer width),' ',integer width
    empty =. width$'0'
    margin =. (quiet*scale)$'0'
    lines =. lines,(quiet*scale)$<empty
    for_row. (n,n)$y do.
        pixels =. margin,(scale#'01'{~row),margin
        lines =. lines,scale$<pixels
    end.
    lines,(quiet*scale)$<empty
)
