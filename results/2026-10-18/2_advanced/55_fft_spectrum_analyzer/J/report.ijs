intdiv =: 4 : '<.(x:x)%x:y'
integer =: 3 : 0
    text =. ":y
    '-'(I.text='_')}text
)
join =: 4 : 0
    result =. ''
    for_j. i.#y do.
        if. j do.
            result =. result,x
        end.
        result =. result,j{::y
    end.
    result
)
real_text =: 3 : 0
    rounded =. x:<.0.5+10000.0*|y
    sign =. ((y<0.0)*.rounded~:0)#'-'
    tail =. integer 10000|rounded
    sign,(integer rounded intdiv 10000),'.',((4-#tail)$'0'),tail
)
write_lines =: 4 : '((LF join y),LF)1!:2 <''output/'',x'
write_csv =: 4 : 0
    'header rows' =. y
    lines =. <header
    for_row. rows do.
        lines =. lines,<','join >row
    end.
    x write_lines lines
)
shade_lines =: 4 : 0
    'sample_rate length band_db maximum' =. x
    levels =. ' .:-=+*#%@'
    rows =. 0$a:
    for_k. |.i.1+<.length%2 do.
        pixels =. ''
        for_frame. y do.
            d =. (20.0*^. (k{frame)%maximum)%2.302585092994046
            level =. 0>.9-<.(-d)%band_db
            pixels =. pixels,level{levels
        end.
        frequency =. real_text (k*sample_rate)%length
        rows =. rows,<((0>.9-#frequency)$' '),frequency,' |',pixels,'|'
    end.
    rows
)
