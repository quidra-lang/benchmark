new_line =: 3 : '(<y),(<i.0),(<i.0),(<_1),(<0),(<_1),<_1'
new_page =: 3 : 0
    'content notes height forced' =. y
    (<content),(<notes),(<height),(<forced),(<0),(<0),(<0),(<0),(<''),(<''),(<''),<0$a:
)
choose_pages =: 3 : 0
    'blocks footnote_heights height orphan widow' =. y
    lines =. 0$a:
    boundaries =. 0 3$0
    for_index. i.#blocks do.
        'kind content list_mark page_break' =. index{::blocks
        start =. #lines
        lines =. lines,content
        count =. #content
        if. kind-:'flow' do.
            for_kept. 1+i.count-1 do.
                if. (kept>:orphan)*.(count-kept)>:widow do.
                    boundaries =. boundaries,(start+kept),(start+kept),0
                end.
            end.
        end.
        if. index=(#blocks)-1 do.
            boundaries =. boundaries,(#lines),(#lines),1
        else.
            following =. (index+1){::blocks
            end =. #lines
            if. -.list_mark*.2{::following do.
                lines =. lines,<new_line ''
            end.
            forced =. 3{::following
            if. forced+.-.kind-:'heading' do.
                boundaries =. boundaries,end,(#lines),forced
            end.
        end.
    end.
    pages =. 0$a:
    start =. 0
    first_boundary =. 0
    while. start<#lines do.
        notes =. (#footnote_heights)$0
        note_height =. 0
        scanned =. start
        chosen =. _1
        used =. 0
        chosen_notes =. i.0
        for_index. first_boundary+i.(#boundaries)-first_boundary do.
            'end next_start forced' =. index{boundaries
            while. scanned<end do.
                for_number. 1{::scanned{::lines do.
                    if. -.number{notes do.
                        notes =. 1 number}notes
                        note_height =. note_height+number{footnote_heights
                    end.
                end.
                scanned =. scanned+1
            end.
            page_notes =. I.notes
            current_height =. ((end-start)+note_height)+0<#page_notes
            if. current_height>height do.
                break.
            end.
            chosen =. index
            used =. current_height
            chosen_notes =. page_notes
            if. forced do.
                break.
            end.
        end.
        'end next_start forced' =. chosen{boundaries
        content =. (start+i.end-start){lines
        pages =. pages,<new_page (<content),(<chosen_notes),(<used),<forced
        start =. next_start
        first_boundary =. chosen+1
    end.
    pages
)
