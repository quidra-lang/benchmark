main =: 3 : 0
  inputs =. '(a + b) * [c - d]';'{x = [1, 2, (3 + 4)]}';'f(a[i] + g(b)}';'(1 + 2)) * 3';'if (a < b) { c = d[0]; }';'((a + b] * c';'[{(x * y) - z}'
  openings =. '([{'
  closings =. ')]}'
  for_box. inputs do.
    text =. >box
    stack =. ''
    failure =. _1
    for_i. i.#text do.
      char =. i{text
      if. char e.openings do.
        stack =. stack,char
      elseif. char e.closings do.
        if. 0=#stack do. failure =. i break. end.
        if. ({:stack)~:(closings i.char){openings do. failure =. i break. end.
        stack =. }:stack
      end.
    end.
    if. (failure=_1)*.0<#stack do. failure =. #text end.
    result =. 'balanced'
    if. failure>:0 do. result =. 'error at index ',":failure end.
    smoutput text,' -> ',result
  end.
)
main ''
