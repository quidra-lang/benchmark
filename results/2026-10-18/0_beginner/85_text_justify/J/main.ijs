split =: 4 : 0
  <;._1 x,y
)

main =: 3 : 0
  paragraph =. 'Good software is written for people first and for machines second. A clear program explains its purpose through careful names, small functions and honest tests. When a team agrees on shared rules for internationalization, documentation and code review, every newcomer can read the code quickly, change it safely and ship new improvements with confidence instead of fear, week after week.'
  words =. ' ' split paragraph
  lines =. 0$<0$<''
  current =. 0$<''
  length =. 0
  for_word. words do.
    size =. #>word
    candidate =. length+size+0<#current
    if. candidate>30 do.
      lines =. lines,<current
      current =. 0$<''
      length =. 0
    end.
    length =. length+size+0<#current
    current =. current,word
  end.
  if. #current do. lines =. lines,<current end.
  for_index. i.#lines do.
    line =. >index{lines
    if. ((index+1)=#lines)+.1=#line do.
      result =. }. ; (<' ') ,&.> line
      result =. result,(30-#result)$' '
    else.
      letters =. +/#&>line
      gaps =. <:#line
      spaces =. 30-letters
      base =. <.spaces%gaps
      extra =. gaps|spaces
      result =. ''
      for_i. i.#line do.
        if. i>0 do. result =. result,(base+i<:extra)$' ' end.
        result =. result,>i{line
      end.
    end.
    smoutput '|',result,'|'
  end.
)
main ''
