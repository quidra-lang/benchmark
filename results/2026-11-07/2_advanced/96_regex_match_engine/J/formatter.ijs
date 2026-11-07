decimal=:3 : '((":y) rplc ''_'';''-'')'
join=:4 :0
  if.  0=#y  do.  ''  else.  }. ;(x&,)&.>y  end.
)
quote=:3 :0
 r=.'"'
  for_c. y  do.
   select. >c
   case. '\'  do.  r=.r,'\\'
   case. '"'  do.  r=.r,'\"'
   case. LF  do.  r=.r,'\n'
   case. 9{a.  do.  r=.r,'\t'
   case.  do.  r=.r,>c
   end.
  end.
 r,'"'
)
unquote=:3 :0
 s=.}.}:y
 r=.''
 p=.0
  while. p<#s  do.
  c=.p{s
  p=.p+1
   if. c='\'  do.
   c=.p{s
   p=.p+1
    if. c='n'  do. c=.LF  elseif. c='t'  do. c=.9{a.  end.
   end.
  r=.r,c
  end.
 r
)
display_char=:3 :0
 c=.a.i.y
  if.  (c>:33)*.(c<:126)*.-.y e.'\]^-'  do.  y  else.  '\x','0123456789ABCDEF'{~16 16#:c  end.
)
set_notation=:3 :0
 's neg'=.y
 s=./:~~.s
 r=.'['
  if. neg  do. r=.r,'^'  end.
  while. #s  do.
  n=.1
   while. n<#s  do.
    if. (n{s)~:({.s)+n  do.  break.  end.
   n=.n+1
   end.
  r=.r,display_char a.{~{.s
   if. n=2  do. r=.r,display_char a.{~1{s  elseif. n>2  do. r=.r,'-',display_char a.{~(n-1){s  end.
  s=.n}.s
  end.
 r,']'
)
format_instruction=:3 :0
 'op arg'=.y
  select. op
  case. 'CHAR'  do. op,' ',display_char arg
  case. 'CLASS'  do. op,' ',set_notation arg
  case. 'SPLIT'  do. op,' ',(decimal 0{arg),', ',decimal 1{arg
  case. 'LOOK'  do. op,' ',(0{::arg),' ',decimal 1{::arg
  case. 'SAVE';'JMP';'BACKREF'  do. op,' ',decimal arg
  case. 'ASSERT'  do. op,' ',arg
  case.  do. op
  end.
)
write_lines=:4 :0
 (;(,&LF)&.>y) 1!:2 <x
)
