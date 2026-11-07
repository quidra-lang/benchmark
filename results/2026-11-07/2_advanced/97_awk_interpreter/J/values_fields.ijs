dec=:3 : '(":y) rplc ''_'';''-'''
number=:3 : '0;'''';y'
string=:3 : '1;y;0'
uninitialized=:3 : '3;'''';0'
parse_numeric=:3 :0
 s=.y
  p=.0
  sign=.1
  while. p<#s  do.  if. -.(p{s)e.' ',LF,9{a. do.  break.  end.
  p=.p+1 end.
  if. p<#s  do.  if. (p{s)e.'+-' do.  if. '-'=p{s  do. sign=._1 end.
  p=.p+1 end.  end.
 start=.p
  while. p<#s  do.  if. -.(p{s)e.digits  do.  break.  end.
  p=.p+1 end.
  if. p=start  do. 0 else. sign*0".(p-start){.start}.s  end.
)
input_value=:3 :0
 s=.y
  trimmed=.deb s rplc LF;' ';(9{a.);' '
 body=.trimmed
  if. #body  do.  if. ({.body)e.'+-' do. body=.}.body  end.  end.
  if. (#body)*.*./body e.digits  do. 2;s;parse_numeric s  else. string s  end.
)
to_number=:3 :0
 'kind s n'=.y
  if. kind e.0 2 do. n  elseif. kind=3 do. 0 else. parse_numeric s  end.
)
to_string=:3 :0
 'kind s n'=.y
  if. kind=0 do. dec n  elseif. kind=3 do. '' else. s  end.
)
truth=:3 :0
 'kind s n'=.y
  if. kind e.0 2 do. n~:0 elseif. kind=3 do. 0 else. 0<#s  end.
)
compare=:4 :0
 a=.x
  b=.y
  if. ((0{::a)e.0 2 3)*.(0{::b)e.0 2 3 do. (* (to_number a)-to_number b)
  else.
  a=.to_string a
  b=.to_string b
   if. a-:b  do. 0 elseif. 0={. /:(<a),<b  do. _1 else. 1 end.
  end.
)
split_string=:4 :0
 separator=.x
  s=.y
  pieces=.0$a:
  if. separator-:' ' do.
  p=.0
   while. p<#s  do.
    while. p<#s  do.  if. -.(p{s)e.' ',LF,9{a. do.  break.  end.
  p=.p+1 end.
   start=.p
    while. p<#s  do.  if. (p{s)e.' ',LF,9{a. do.  break.  end.
  p=.p+1 end.
    if. p>start  do. pieces=.pieces,<(p-start){.start}.s  end.
   end.
  elseif. 0=#separator  do. pieces=.<"0 s
  elseif. #s  do.
  start=.0
  p=.0
   while. p+#separator<:#s  do.
    if. separator-:(#separator){.p}.s  do. pieces=.pieces,<(p-start){.start}.s
  p=.p+#separator
  start=.p  else. p=.p+1 end.
   end.
  pieces=.pieces,<start}.s
  end.
 pieces
)
set_record=:3 :0
 Record=:input_value y
 fs=.to_string scalar_global 'FS'
 pieces=.fs split_string y
 Fields=:input_value&.>pieces
)
rebuild_record=:3 :0
 sep=.to_string scalar_global 'OFS'
 strings=.to_string&.>Fields
 Record=:input_value sep join strings
)
field_value=:3 :0
  if. y=0 do. Record  elseif. y>#Fields  do. uninitialized'' else. (y-1){::Fields  end.
)
set_field=:4 :0
 k=.x
  v=.y
  if. k=0 do. set_record to_string v
  else.
   while. k>#Fields  do. Fields=:Fields,<string'' end.
  Fields=:(<v)(k-1)}Fields
  rebuild_record''
  end.
 field_value k
)
set_nf=:3 :0
 n=.to_number y
  if. n<0 do. runtime_error 'negative NF' end.
  while. n>#Fields  do. Fields=:Fields,<string'' end.
 Fields=:n{.Fields
 rebuild_record''
 number n
)
integer_key=:3 :0
 s=.y
  if. s-:'0' do. 1 return.  end.
  if. 0=#s  do. 0 return.  end.
  if. '-'={.s  do. s=.}.s  end.
  if. 0=#s  do. 0 return.  end.
 (({.s)e.'123456789')*.*./s e.digits
)
key_order=:3 :0
 integers=.0$a:
  other=.0$a:
  nums=.i.0
  for_s. y  do.  if. integer_key >s  do. integers=.integers,s
  nums=.nums,parse_numeric >s  else. other=.other,s  end.  end.
 ((/:nums){integers),/:~other
)
value_text=:3 :0
 'kind s n'=.y
  if. kind=0 do. dec n  return.  end.
  if. kind=3 do. '(uninitialized)' return.  end.
 r=.'"'
  for_c. s  do.
  c=.>c
  code=.a.i.c
   select. c
   case. '"' do. r=.r,'\"'
   case. '\' do. r=.r,'\\'
   case. LF do. r=.r,'\n'
   case. 9{a. do. r=.r,'\t'
   case.  do.  if. (code<32)+.code>126 do. r=.r,'\','01234567'{~8 8 8#:code  else. r=.r,c  end.
   end.
  end.
 r=.r,'"'
  if. kind=2 do. r=.r,' (strnum)' end.
 r
)
join=:4 :0
  if. 0=#y  do. '' else. (#x)}.;(x&,)&.>y  end.
)
