write_ppm =: 3 : 0
    lines =. (<'P3'),(<(number Width),' ',number Height),<'255'
    for_py. i.Height do. lines =. lines,<' ' join number&.><"0 ,(Width{.(py*Width)}.y) end.
    'image.ppm' write_lines lines
)
write_preview =: 3 : 0
    ramp =. '@%#*+=-:,.'
    lines =. 0$a:
    for_top. 4*i.Height div 4 do.
        text =. ''
        for_left. 2*i.Width div 2 do.
            total =. 0
            for_py. top+i.4 do.
                for_px. left+i.2 do. total =. total++/299 587 114*((py*Width)+px){y end.
            end.
            brightness =. total div 8000
            text =. text,((brightness*10) div 256){ramp
        end.
        lines =. lines,<text
    end.
    'preview.txt' write_lines lines
)
