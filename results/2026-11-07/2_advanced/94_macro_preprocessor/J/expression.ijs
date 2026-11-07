Levels=:('||';'&&';'|';'^';'&'),(<(<;._1 ' ','== !=')),(<(<;._1 ' ','< > <= >=')),(<(<;._1 ' ','<< >>')),(<(<;._1 ' ','+ -')),<(<;._1 ' ','* / %')
expression_error=:3 :0
 error y
 13!:8]3
)
expr_node=:4 :0
 n=.cocreate''
 op__n=:x
  children__n=:y
  value__n=:0
 n
)
expr_peek=:3 :0
  if. EPos=#ETokens  do. '' else. t=.EPos{ETokens
  spell__t  end.
)
constant_value=:3 :0
 t=.y
  s=.spell__t
  if. kind__t-:'character' do.
  body=.}.}:s
   if. (1=#body)*.-.body e.'''\' do. a.i.{.body  return.  end.
   if. (2=#body)*.'\'={.body  do.
   i=.'nt\''"0'i.{:body
    if. i<6 do. i{10 9 92 39 34 0 return.  end.
   end.
  expression_error 'invalid character constant ',s
  end.
 original=.s
  for_suffix. 'll';'LL';'l';'L' do. suffix=.>suffix
   if. ((#s)>#suffix)*.suffix-:(-#suffix){.s  do. s=.(-#suffix)}.s
   break.  end.
  end.
 base=.10
  chars=.digits
  if. (<2{.s)e.'0x';'0X' do. base=.16
  chars=.'0123456789abcdef'
  s=.tolower 2}.s
  elseif. '0'={.s  do. base=.8
  chars=.'01234567' end.
  if. (0=#s)+.-.*./s e.chars  do. expression_error 'invalid integer constant "',original,'"' end.
 base #. chars i.s
)
expr_unary=:3 :0
 s=.expr_peek''
  if. (<s)e.'+';'-';'!';'~' do. EPos=:EPos+1
  s expr_node ,expr_unary'' return.  end.
  if. 0=#s  do. expression_error 'expected value at end of expression' end.
 t=.EPos{ETokens
  EPos=:EPos+1
  if. s-:'(' do.
  n=.expr_conditional''
   if. -.')'-:expr_peek'' do. expression_error 'missing '')'' in expression' end.
  EPos=:EPos+1
  n
  elseif. (<kind__t)e.'number';'character' do. n=.'constant'expr_node 0$a:
  value__n=:constant_value t
  n
  elseif. kind__t-:'identifier' do. n=.'identifier'expr_node 0$a:
  value__n=:s
  n
  else. expression_error 'expected value before "',s,'"' end.
)
expr_binary=:3 :0
 level=.y
  if. level=10 do. expr_unary'' return.  end.
 left=.expr_binary level+1
 ops=.level{::Levels
  if. 2=3!:0 ops  do. ops=.,<ops  end.
  while. (<expr_peek'')e.ops  do.
  op=.expr_peek''
  EPos=:EPos+1
  right=.expr_binary level+1
  left=.op expr_node left,right
  end.
 left
)
expr_conditional=:3 :0
 left=.expr_binary 0
  if. '?'-:expr_peek'' do.
  EPos=:EPos+1
  middle=.expr_conditional''
   if. -.':'-:expr_peek'' do. expression_error '''?'' without following '':'' ' end.
  EPos=:EPos+1
  left=.'?'expr_node left,middle,expr_conditional''
  end.
 left
)
evaluate_expr=:3 :0
 n=.y
  op=.op__n
  if. op-:'constant' do. value__n  return.  end.
  if. op-:'identifier' do. warning 'identifier "',value__n,'" evaluates to 0'
  0 return.  end.
 a=.evaluate_expr 0{children__n
  if. op-:'?' do.  if. a~:0 do. evaluate_expr 1{children__n  else. evaluate_expr 2{children__n  end.  return.  end.
  if. 1=#children__n  do.
   select. op
   case. '+' do. a
   case. '-' do. -a
   case. '!' do. a=0
   case. '~' do. -a+1
   end.  return.
  end.
  if. (op-:'&&')*.a=0 do. 0 return.  end.
  if. (op-:'||')*.a~:0 do. 1 return.  end.
 b=.evaluate_expr 1{children__n
  if. ((<op)e.'/';'%')*.b=0 do. expression_error 'division by zero in #if' end.
  select. op
  case. '+' do. a+b
  case. '-' do. a-b
  case. '*' do. a*b
  case. '/' do. (*a%b)*<.|a%b
  case. '%' do. a-b*(*a%b)*<.|a%b
  case. '<' do. a<b
  case. '>' do. a>b
  case. '<=' do. a<:b
  case. '>=' do. a>:b
  case. '==' do. a=b
  case. '!=' do. a~:b
  case. '&&' do. b~:0
  case. '||' do. b~:0
  case. '<<' do. a*2^b
  case. '>>' do. <.a%2^b
  case. '&' do. a(17 b.)b
  case. '|' do. a(23 b.)b
  case. '^' do. a(22 b.)b
  end.
)
