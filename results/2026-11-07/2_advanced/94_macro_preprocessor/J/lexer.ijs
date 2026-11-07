LF=:10{a.
letters=:'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
digits=:'0123456789'
identchars=:letters,digits,'_'
punctuators=:(<;._1 ' ','... <<= >>= -> ++ -- << >> <= >= == != && || *= /= %= += -= &= ^= |= ## [ ] ( ) { } . & * + - ~ ! / % < > ^ | ? : ; = , #')
dec=:3 : '(":y) rplc ''_'';''-'''
readlines=:3 : '<;._2 (1!:1 <y)'
join=:4 :0
  if. 0=#y  do. '' else. (#x)}.;(x&,)&.>y  end.
)
write_lines=:4 : '(;(,&LF)&.>y) 1!:2 <x'
token=:3 :0
 'kind spell line space'=.y
 t=.cocreate''
 kind__t=:kind
  spell__t=:spell
  line__t=:line
  space__t=:space
  hide__t=:0$a:
 t
)
clone_token=:3 :0
 s=.y
 t=.token kind__s;spell__s;line__s;space__s
 hide__t=:hide__s
 t
)
clone_tokens=:3 :0
 result=.0$a:
  for_t. y  do. result=.result,clone_token t  end.
 result
)
spellings=:3 :0
 result=.0$a:
  for_t. y  do. result=.result,<spell__t  end.
 result
)
raw_token=:4 :0
 p=.x
  text=.y
  c=.p{text
  n=.1
  kind=.'other'
  if. c e.letters,'_' do. kind=.'identifier'
   while. p+n<#text  do.  if. -.((p+n){text)e.identchars  do.  break.  end.
  n=.n+1 end.
  elseif. (c e.digits)+.((c='.')*.((p+1){text,0{a.)e.digits) do.
  kind=.'number'
   while. p+n<#text  do.
   c=.(p+n){text
    if. (c e.'eEpP')*.((p+n+1){text,0{a.)e.'+-' do. n=.n+2
    elseif. c e.identchars,'.' do. n=.n+1 else.  break.  end.
   end.
  elseif. c e.'''"' do.
  j=.p+1
   while. j<#text  do.
   d=.j{text
    if. d=LF do.  break.  end.
    if. d=c  do. n=.1+j-p
  kind=.('character';'string'){::~c='"'
   break.  end.
    if. (d='\')*.((j+1){text,LF)~:LF do. j=.j+2 else. j=.j+1 end.
   end.
  else.
   for_punct. punctuators  do. punct=.>punct
    if. punct-:(#punct){.p}.text  do. kind=.'punctuator'
  n=.#punct
   break.  end.
   end.
  end.
 n;kind;n{.p}.text
)
single_token=:3 :0
  if. (0=#y)+.((<2{.y)e.'//';'/*') do. 0;'' return.  end.
 'n kind spell'=.0 raw_token y
 (n=#y);kind
)
render=:3 :0
 result=.''
  for_t. y  do.  if. (#result)*.space__t  do. result=.result,' ' end.
  result=.result,spell__t  end.
 result
)
needs_separator=:4 :0
 l=.spell__x
  r=.spell__y
  if. (l-:'/')*.({.r)e.'/*' do. 1 return.  end.
 'n kind spell'=.0 raw_token l,r
 n~:#l
)
output_render=:3 :0
 result=.''
  previous=.a:
  for_t. y  do.
   if. #result  do.  if. space__t+.previous needs_separator t  do. result=.result,' ' end.  end.
  result=.result,spell__t
  previous=.t
  end.
 result
)
lex_source=:3 :0
 raw=.y
  text=.''
  physical=.i.0
  line=.1
  p=.0
  while. p<#raw  do.
  c=.p{raw
   if. (c='\')*.LF=(p+1){raw,0{a. do. p=.p+2
  line=.line+1
   continue.  end.
  text=.text,c
  physical=.physical,line
   if. c=LF do. line=.line+1 end.
  p=.p+1
  end.
 result=.0$a:
  ts=.0$a:
  start=.1
  space=.1
  p=.0
  while. p<#text  do.
  c=.p{text
   if. c=' ' do. space=.1
  p=.p+1
   continue.  end.
   if. c=LF do.
   l=.cocreate''
  tokens__l=:ts
  start__l=:start
  end__l=:p{physical
   result=.result,l
  start=.1+p{physical
  ts=.0$a:
  p=.p+1
  space=.1
   continue.
   end.
   if. '/*'-:2{.p}.text  do.
   p=.p+2
    while. -.'*/'-:2{.p}.text  do. p=.p+1 end.
   p=.p+2
  space=.1
   continue.
   end.
   if. '//'-:2{.p}.text  do.  while. LF~:p{text  do. p=.p+1 end.
  space=.1
   continue.  end.
  header=.0
   if. (c='<')*.('#';'include')-:spellings ts  do.
   last=.(p}.text)i.'>'
  newline=.(p}.text)i.LF
   header=.last<newline
   end.
   if. header  do. n=.last+1
  kind=.'header'
  spell=.n{.p}.text  else. 'n kind spell'=.p raw_token text  end.
  ts=.ts,token kind;spell;(p{physical);space
  p=.p+n
  space=.0
  end.
 result
)
lex_line=:3 :0
 ls=.lex_source y,LF
 l=.{.ls
 tokens__l
)
