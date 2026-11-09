Symbols =: '?#.'
state_char =: 3 : 'y{Symbols'
char_state =: 3 : 'Symbols i.y'
state_string =: state_char
state_grid =: 3 : '((#y),#0{::y)$char_state ;y'
right_align =: 4 : '((x-#y)#'' ''),y'
grid_display =: 3 : 0
    'names grids' =. y
    lines =. <'grid ',' ' join names
    for_row. i.{.$0{::grids do.
        parts =. 0$a:
        for_box. grids do. parts =. parts,<state_string row{>box end.
        lines =. lines,<' | ' join parts
    end.
    lines
)
answer_sheet =: 3 : 0
    'rows columns grid' =. y
    tokens =. 0$a:
    width =. depth =. margin =. 0
    for_box. columns do.
        column =. ' ' split ' ' clue_text >box
        tokens =. tokens,<column
        depth =. depth>.#column
        for_tokenbox. column do. width =. width>.#>tokenbox end.
    end.
    width =. width+1
    for_box. rows do. margin =. margin>.#' ' clue_text >box end.
    lines =. 0$a:
    for_line. i.depth do.
        text =. margin#' '
        for_box. tokens do.
            column =. >box
            skip =. depth-#column
            if. line>:skip do. text =. text,width right_align (line-skip){::column
            else. text =. text,width#' ' end.
        end.
        text =. text{.~>:>./_1,I.text~:' '
        lines =. lines,<text
    end.
    for_row. i.#rows do.
        text =. margin right_align ' ' clue_text row{::rows
        for_state. row{grid do. text =. text,((width-1)#' '),state_char state end.
        lines =. lines,<text
    end.
    lines
)
