LF=:10{a.
readlines=:3 : '<;._2 (1!:1 <y)'
dec=:3 : '(":y) rplc ''_'';''-'''
num=:3 : '0".y rplc ''-'';''_'''
words=:3 :0
 s=.deb y
 if. 0=#s do. 0$a: else. <;._1 ' ',s end.
)
join=:4 :0
  if. 0=#y  do. '-' else. (#x)}.;(x&,)&.>y  end.
)
write_lines=:4 : '(;(,&LF)&.>y) 1!:2 <x'
isconst=:3 : '((#y)>0)*.({.y)e.''-0123456789'''
Kinds=:(<;._1 ' ','copy bin load store goto if param call return read print')
new_instruction=:3 :0
 s=.cocreate''
 kind__s=:y
 dest__s=:a__s=:b__s=:op__s=:array__s=:target__s=:callee__s=:''
 count__s=:0
 s
)
clone=:3 :0
 s=.y
 t=.new_instruction kind__s
 dest__t=:dest__s
  a__t=:a__s
  b__t=:b__s
  op__t=:op__s
  array__t=:array__s
  target__t=:target__s
  callee__t=:callee__s
  count__t=:count__s
 t
)
parse_index=:3 :0
 p=.y i.'['
 (p{.y);}.}:p}.y
)
parse_instruction=:3 :0
 w=.words y
  if. ':'={:0{::w  do. s=.new_instruction 'label'
  target__s=:}:0{::w
  s  return.  end.
 first=.0{::w
  if. (<first)e.(<;._1 ' ','goto if param call return read print') do.
  s=.new_instruction first
   select. first
   case. 'goto' do. target__s=:1{::w
   case. 'if' do. a__s=:1{::w
  op__s=:2{::w
  b__s=:3{::w
  target__s=:5{::w
   case. 'call' do. callee__s=:1{::w
  count__s=:num 2{::w
   case. 'read' do. dest__s=:1{::w
   case.  do.  if. 1<#w  do. a__s=:1{::w  end.
   end.
  elseif. '['e.first  do.
  s=.new_instruction 'store'
  'arr index'=.parse_index first
  array__s=:arr
  a__s=:index
  b__s=:2{::w
  else.
  rhs=.2{::w
   if. rhs-:'call' do. s=.new_instruction 'call'
  callee__s=:3{::w
  count__s=:num 4{::w
   elseif. 5=#w  do. s=.new_instruction 'bin'
  a__s=:rhs
  op__s=:3{::w
  b__s=:4{::w
   elseif. '['e.rhs  do. s=.new_instruction 'load'
  'arr index'=.parse_index rhs
  array__s=:arr
  a__s=:index
   else. s=.new_instruction 'copy'
  a__s=:rhs  end.
  dest__s=:first
  end.
 s
)
parse_program=:3 :0
 fs=.0$a:
  Arrays=:0$a:
  for_line. y  do.
  w=.words >line
   if. 0=#w  do.  continue.  end.
   if. '#'={.0{::w  do.  continue.  end.
   select. 0{::w
   case. 'array' do. Arrays=:Arrays,<((1{::w);num 2{::w)
   case. 'func' do. f=.cocreate''
  name__f=:1{::w
  params__f=:2}.w
  code__f=:0$a:
  temp__f=:0
  pre__f=:0
  fs=.fs,f
   case. 'end' do.
   case.  do. code__f=:code__f,parse_instruction >line
   end.
  end.
 fs
)
used=:3 :0
 s=.y
  if. (<kind__s)e.(<;._1 ' ','bin if store') do. vs=.(<a__s),<b__s
  elseif. (<kind__s)e.(<;._1 ' ','copy load param return print') do. vs=.,<a__s
  else. vs=.0$a: end.
 r=.0$a:
  for_v. vs  do.  if. (#>v)*.-.isconst >v  do. r=.r,v  end.  end.
 r
)
expression=:3 :0
 s=.y
  if. kind__s-:'bin' do. a__s,op__s,b__s
  elseif. kind__s-:'load' do. array__s,'[',a__s,']'
  else. '' end.
)
expr_uses=:3 :0
 s=.y
  if. kind__s-:'bin' do. used s
  elseif. kind__s-:'load' do.  if. isconst a__s  do. 0$a: else. ,<a__s  end.
  else. 0$a: end.
)
operation=:4 :0
 'a b'=.y
  select. x
  case. '+' do. a+b
  case. '-' do. a-b
  case. '*' do. a*b
  case. '/' do. (*a%b)*<.|a%b
  case. '%' do. a-b*(*a%b)*<.|a%b
  case. '<' do. a<b
  case. '<=' do. a<:b
  case. '>' do. a>b
  case. '>=' do. a>:b
  case. '==' do. a=b
  case. '!=' do. a~:b
  end.
)
instruction_text=:3 :0
 s=.y
  select. kind__s
  case. 'label' do. target__s,':'
  case. 'copy' do. dest__s,' = ',a__s
  case. 'bin' do. dest__s,' = ',a__s,' ',op__s,' ',b__s
  case. 'load' do. dest__s,' = ',array__s,'[',a__s,']'
  case. 'store' do. array__s,'[',a__s,'] = ',b__s
  case. 'goto' do. 'goto ',target__s
  case. 'if' do. 'if ',a__s,' ',op__s,' ',b__s,' goto ',target__s
  case. 'call' do. r=.'call ',callee__s,' ',dec count__s
   if. #dest__s  do. r=.dest__s,' = ',r  end.
  r
  case. 'read' do. 'read ',dest__s
  case.  do. kind__s,((#a__s)>0)#' ',a__s
  end.
)
function_lines=:3 :0
 f=.y
 r=.,<'func ',name__f
  if. #params__f  do. r=.,<'func ',name__f,' ',' 'join params__f  end.
  for_s. code__f  do.
  line=.instruction_text s
   if. -.kind__s-:'label' do. line=.'    ',line  end.
  r=.r,<line
  end.
 r,<'end'
)
program_lines=:3 :0
 r=.0$a:
  for_arr. Arrays  do. 'name size'=.>arr
  r=.r,<'array ',name,' ',dec size  end.
  for_f. y  do.  if. #r  do. r=.r,<'' end.
  r=.r,function_lines f  end.
 r
)
