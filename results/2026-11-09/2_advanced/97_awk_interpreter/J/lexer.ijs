LF=:10{a.
letters=:'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
digits=:'0123456789'
namechars=:letters,digits,'_'
Keywords=:(<;._1 ' ','BEGIN END function if else while for do break continue next exit return delete in getline print printf')
Builtins=:(<;._1 ' ','length substr index split sprintf toupper tolower close int')
Symbols=:(<;._1 ' ','+= -= *= /= %= ^= == <= >= != ++ -- && || >> + - * / % ^ ! > < ? : = ( ) [ ] { } , ; $')
syntax_error=:3 :0
 SyntaxPosition=:y
 13!:8]3
)
lex=:3 :0
 text=.y
  p=.0
  line=.1
  col=.1
  tokens=.0$a:
  while. p<#text  do.
  c=.p{text
   if. c=' ' do. p=.p+1
  col=.col+1
   continue.  end.
   if. (c='\')*.LF=(p+1){text,0{a. do. p=.p+2
  line=.line+1
  col=.1
   continue.  end.
   if. c='#' do.  while. LF~:p{text  do. p=.p+1
  col=.col+1 end.
   continue.  end.
  at=.col
  start=.p
  kind=.'symbol'
  value=.''
   if. c=LF do. kind=.'newline'
  value=.'NL'
  p=.p+1
   elseif. c e.digits  do.
   kind=.'number'
    while. p<#text  do.  if. -.(p{text)e.digits  do.  break.  end.
  p=.p+1 end.
   value=.(p-start){.start}.text
   elseif. c e.letters,'_' do.
   p=.p+1
    while. p<#text  do.  if. -.(p{text)e.namechars  do.  break.  end.
  p=.p+1 end.
   value=.(p-start){.start}.text
    if. (<value)e.Keywords  do. kind=.'keyword'
    elseif. (<value)e.Builtins  do. kind=.'builtin'
    elseif. '('=(p{text,0{a.) do. kind=.'function'
    else. kind=.'name' end.
   elseif. c='"' do.
   kind=.'string'
  p=.p+1
  closed=.0
    while. p<#text  do.
    c=.p{text
     if. c=LF do. syntax_error line,at  end.
    p=.p+1
     if. c='"' do. closed=.1
   break.  end.
     if. c='\' do.
      if. p=#text  do. syntax_error line,at  end.
     c=.p{text
  p=.p+1
      if. -.c e.'nt\"/' do. syntax_error line,(at+p-start-2) end.
      if. c='n' do. c=.LF elseif. c='t' do. c=.9{a. end.
     end.
    value=.value,c
    end.
    if. -.closed  do. syntax_error line,at  end.
   else.
    for_s. Symbols  do. s=.>s
     if. s-:(#s){.p}.text  do. value=.s
  p=.p+#s
   break.  end.
    end.
    if. 0=#value  do. syntax_error line,at  end.
   end.
  t=.cocreate''
  kind__t=:kind
  value__t=:value
  line__t=:line
  column__t=:at
  tokens=.tokens,t
   if. kind-:'newline' do. line=.line+1
  col=.1 else. col=.col+p-start  end.
  end.
 t=.cocreate''
 kind__t=:'eof'
  value__t=:'EOF'
  line__t=:line
  column__t=:1
 tokens,t
)
