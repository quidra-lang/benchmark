InfixNames=:(<;._1 ' ',':- ; -> , = \= == \== is =:= =\= < > =< >= =.. + - * / // mod rem')
InfixPriority=:1200 1100 1050 1000,13$700
InfixPriority=:1200 1100 1050 1000 700 700 700 700 700 700 700 700 700 700 700 700 500 500 400 400 400 400 400
InfixType=:('xfx';'xfy';'xfy';'xfy'),(12$<'xfx'),(7$<'yfx')
PrefixNames=:'\+';'-'
PrefixPriority=:900 200
new_token=:3 :0
 'kind name spelling line column space'=.y
 t=.cocreate''
 kind__t=:kind
  name__t=:name
  spelling__t=:spelling
  line__t=:line
  column__t=:column
  space__t=:space
 t
)
lex=:4 :0
 text=.y
 result=.0$a:
  p=.0
  line=.1
  col=.x
  whitespace=.1
  while. p<#text  do.
  c=.p{text
   if. c=' '  do. p=.p+1
  col=.col+1
  whitespace=.1
   continue.  end.
   if. c=LF  do. p=.p+1
  line=.line+1
  col=.1
  whitespace=.1
   continue.  end.
   if. c='%'  do.
    while. p<#text  do.  if. LF=p{text  do.  break.  end.
  p=.p+1
  col=.col+1  end.
   whitespace=.1
   continue.
   end.
  start=.p
  at=.col
  k=.'name'
  name=.''
   if. c e.digits  do.
   p=.p+1
    while. p<#text  do.  if. -.(p{text)e.digits  do.  break.  end.
  p=.p+1  end.
   name=.(p-start){.start}.text
    if. (0".name)>2147483647  do. k=.'invalid'
  name=.'integer too large' else. k=.'integer' end.
   elseif. c e.letters,'_'  do.
   p=.p+1
    while. p<#text  do.  if. -.(p{text)e.alnum  do.  break.  end.
  p=.p+1  end.
   name=.(p-start){.start}.text
    if. -.c e.'abcdefghijklmnopqrstuvwxyz'  do. k=.'variable' end.
   elseif. c e.symbols  do.
   p=.p+1
    while. p<#text  do.  if. -.(p{text)e.symbols  do.  break.  end.
  p=.p+1  end.
   name=.(p-start){.start}.text
    if. name-:'.' do.  if. p=#text  do. k=.'end' elseif. (p{text)e.' %',LF  do. k=.'end' end.  end.
   elseif. c e.'!;'  do. name=.,c
  p=.p+1
   elseif. c e.',|()[]'  do. k=.'punct'
  name=.,c
  p=.p+1
   elseif. c=''''  do.
   k=.'quoted'
  p=.p+1
  escaped=.0
  closed=.0
    while. p<#text  do.
    c=.p{text
     if. c=LF  do.  break.  end.
    p=.p+1
     if. c=''''  do.
      if. p<#text  do.  if. ''''=p{text  do. name=.name,''''
  p=.p+1
   continue.  end.  end.
     closed=.1
   break.
     elseif. c='\'  do.
      if. p=#text  do.  continue.  end.
     d=.p{text
      if. d=LF  do.  continue.  end.
     p=.p+1
      select. d
      case. 'n'  do. name=.name,LF
      case. 't'  do. name=.name,9{a.
      case. '\';''''  do. name=.name,d
      case.  do. escaped=.1
      end.
     else. name=.name,c  end.
    end.
    if. -.closed  do. k=.'invalid'
  name=.'unterminated quoted atom'
    elseif. escaped  do. k=.'invalid'
  name=.'undefined escape sequence' end.
   else. k=.'invalid'
  name=.'illegal character ''',c,''''
  p=.p+1  end.
  spell=.(p-start){.start}.text
  result=.result,new_token k;name;spell;line;at;whitespace
  col=.col+p-start
  whitespace=.0
  end.
 result,new_token 'eof';'';'';line;col;1
)
syntax_error=:3 :0
 t=.y
 ReaderError=:t
  select. kind__t
  case. 'invalid'  do. ReaderMessage=:name__t
  case. 'eof'  do. ReaderMessage=:'unexpected end of file'
  case. 'end'  do. ReaderMessage=:'unexpected end of clause'
  case.  do.
   if. (kind__t-:'name')*.(<name__t)e.InfixNames  do. ReaderMessage=:'operator priority clash'
   else. ReaderMessage=:'unexpected "',spelling__t,'"' end.
  end.
 13!:8]3
)
next_token=:3 : 'ReaderPosition{Tokens'
consume=:3 :0
 t=.next_token''
 ReaderPosition=:ReaderPosition+1
 t
)
expect=:3 :0
 t=.consume''
  if. -.name__t-:y  do. syntax_error t  end.
 t
)
can_start=:3 :0
 t=.y
  if. (<kind__t)e.'integer';'variable';'quoted'  do. 1
  elseif. kind__t-:'punct'  do. (<name__t)e.'('; '['
  elseif. kind__t-:'name'  do. (-.(<name__t)e.InfixNames)+.(<name__t)e.PrefixNames
  else. 0  end.
)
read_primary=:3 :0
 limit=.y
 t=.consume''
  select. kind__t
  case. 'integer'  do. (integer 0".name__t);0
  case. 'variable'  do.
  name=.name__t
  i=.VarNames i.<name
   if. (name-:'_')+.i=#VarNames  do.
   v=.fresh''
    if. -.name-:'_' do. VarNames=:VarNames,<name
  VarTerms=:VarTerms,v
  VarCounts=:VarCounts,1 end.
   else. v=.i{VarTerms
  VarCounts=:(1+i{VarCounts)i}VarCounts  end.
  v;0
  case. 'punct'  do.
   select. name__t
   case. '('  do. 'v priority'=.read_term 1200
  expect ')'
  v;0
   case. '['  do.
   n=.next_token''
    if. name__n-:']' do. consume''
  (atom '[]');0  return.  end.
   es=.0$a:
    while. 1  do. 'v priority'=.read_term 999
  es=.es,v
  n=.next_token''
     if. -.name__n-:',' do.  break.  end.
  consume'' end.
   tail=.atom '[]'
    if. name__n-:'|' do. consume''
  'tail priority'=.read_term 999  end.
   expect ']'
   (es make_list tail);0
   case.  do. syntax_error t
   end.
  case. 'name';'quoted'  do.
  n=.next_token''
   if. (name__n-:'(')*.-.space__n  do.
   consume''
   es=.0$a:
    while. 1  do. 'v priority'=.read_term 999
  es=.es,v
  n=.next_token''
     if. -.name__n-:',' do.  break.  end.
  consume'' end.
   expect ')'
   (name__t compound es);0
   elseif. (kind__t-:'name')*.(name__t-:'-')*.(kind__n-:'integer')*.-.space__n  do. consume''
  (integer -0".name__n);0
   elseif. (kind__t-:'name')*.((<name__t)e.PrefixNames)*.can_start n  do.
   p=.(PrefixNames i.<name__t){PrefixPriority
    if. p>limit  do.
    ReaderError=:t
    ReaderMessage=:'operator priority clash'
    13!:8]3
   end.
   'v priority'=.read_term p
   (name__t compound ,v);p
   else. (atom name__t);0  end.
  case.  do. syntax_error t
  end.
)
read_term=:3 :0
 limit=.y
 'left priority'=.read_primary limit
  while. 1  do.
  t=.next_token''
   if. -.((kind__t-:'name')+.((kind__t-:'punct')*.name__t-:','))  do.  break.  end.
  i=.InfixNames i.<name__t
   if. i=#InfixNames  do.  break.  end.
  p=.i{InfixPriority
  typ=.i{::InfixType
  la=.p-typ~:'yfx'
  ra=.p-typ~:'xfy'
   if. (p>limit)+.priority>la  do.  break.  end.
  consume''
  'right rp'=.read_term ra
  left=.name__t compound left,right
  priority=.p
  end.
 left;priority
)
read_clause=:3 :0
 VarNames=:0$a:
  VarTerms=:0$a:
  VarCounts=:i.0
 't priority'=.read_term 1200
 e=.consume''
  if. -.kind__e-:'end' do. syntax_error e  end.
 t
)
