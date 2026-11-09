runtime_error=:3 :0
 RuntimeMessage=:y
 RuntimePosition=:ErrorPosition
 13!:8]3
)
base_digits=:4 :0
 n=.y
  if. n=0 do. '0' return.  end.
 result=.''
  while. n>0 do. result=.( (x|n){'0123456789abcdef'),result
  n=.<.n%x  end.
 result
)
format_values=:3 :0
 fmt=.to_string 0{::y
  values=.}.y
  p=.0
  index=.0
  result=.''
  while. p<#fmt  do.
  c=.p{fmt
  p=.p+1
   if. c~:'%' do. result=.result,c
   continue.  end.
   if. p=#fmt  do. runtime_error 'invalid format' end.
   if. '%'=p{fmt  do. result=.result,'%'
  p=.p+1
   continue.  end.
  flags=.''
   while. p<#fmt  do.  if. -.(p{fmt)e.'-0' do.  break.  end.
  flags=.flags,p{fmt
  p=.p+1 end.
  start=.p
   while. p<#fmt  do.  if. -.(p{fmt)e.digits  do.  break.  end.
  p=.p+1 end.
  width=.0
   if. p>start  do. width=.0".(p-start){.start}.fmt  end.
  precision=._1
   if. p<#fmt  do.  if. '.'=p{fmt  do.
   p=.p+1
  start=.p
    while. p<#fmt  do.  if. -.(p{fmt)e.digits  do.  break.  end.
  p=.p+1 end.
   precision=.0
    if. p>start  do. precision=.0".(p-start){.start}.fmt  end.
   end.  end.
   if. p=#fmt  do. runtime_error 'invalid format' end.
  c=.p{fmt
  p=.p+1
   if. -.c e.'dis cxo'-. ' ' do. runtime_error 'invalid format' end.
   if. index=#values  do. runtime_error 'not enough arguments' end.
  v=.index{::values
  index=.index+1
   if. c e.'dixo' do.
   n=.to_number v
  base=.10
    if. c='x' do. base=.16 elseif. c='o' do. base=.8 end.
   body=.base base_digits |n
    if. precision~:_1 do.  if. (precision=0)*.n=0 do. body=.'' else. body=.((0>.precision-#body)$'0'),body  end.  end.
    if. n<0 do. body=.'-',body  end.
   elseif. c='s' do. body=.to_string v
   if. precision>:0 do. body=.(precision<.#body){.body  end.
   else.
    if. (0{::v)e.0 2 do.
    n=.to_number v
     if. -.(n=10)+.(n>:32)*.n<:126 do. runtime_error 'invalid character code' end.
    body=.a.{~n
    else. s=.to_string v
    if. #s do. body=.,{.s else. body=.'' end.
   end.
   end.
  padding=.0>.width-#body
   if. '-'e.flags  do. body=.body,padding$' '
   elseif. ('0'e.flags)*.(precision=_1)*.c e.'dixo' do.
    if. ('-'={.body)*.#body  do. body=.'-',(padding$'0'),}.body  else. body=.(padding$'0'),body  end.
   else. body=.(padding$' '),body  end.
  result=.result,body
  end.
 result
)
scalar_builtin=:4 :0
 name=.x
  vs=.y
  select. name
  case. 'length' do. number #to_string 0{::vs
  case. 'substr' do.
  s=.to_string 0{::vs
  m=.to_number 1{::vs
   if. 3=#vs  do. ending=.m+to_number 2{::vs  else. ending=.1+#s  end.
  start=.1>.m
  ending=.ending<.1+#s
  string (0>.ending-start){.(start-1)}.s
  case. 'index' do.
  s=.to_string 0{::vs
  t=.to_string 1{::vs
   if. 0=#t  do. number 0 else. positions=.I.t E.s
   if. #positions  do. number 1+{.positions  else. number 0 end.  end.
  case. 'sprintf' do. string format_values vs
  case. 'toupper' do. string toupper to_string 0{::vs
  case. 'tolower' do. string tolower to_string 0{::vs
  case. 'int' do. number to_number 0{::vs
  end.
)
