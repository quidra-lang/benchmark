bt_execute=:3 :0
 'p q cap partial'=.y
 stack=.,<(p;q;cap;i.0)
  while. #stack  do.
  'p q cap visited'=.>{:stack
  stack=.}:stack
  running=.1
   while. running  do.
   BTSteps=:BTSteps+1
    if. BTSteps>200000  do. BTAborted=:1
  13!:8]3  end.
   ins=.p{::Code
   'op arg'=.ins
    select. op
    case. 'CHAR';'ANY';'CLASS'  do.
     if. ins consumes q  do. q=.q+1
  p=.p+1
  visited=.i.0  else. running=.0  end.
    case. 'SPLIT'  do.
     if. p e.visited  do. running=.0  else.
     visited=.visited,p
     stack=.stack,<((1{arg);q;cap;visited)
     p=.0{arg
     end.
    case. 'JMP'  do. p=.arg
    case. 'SAVE'  do. cap=.q arg}cap
  p=.p+1
    case. 'ASSERT'  do.  if. arg assertion q  do. p=.p+1  else. running=.0  end.
    case. 'BACKREF'  do.
    'a b'=.((2*arg)+0 1){cap
     if. (a<0)+.(b<0)+.a>b  do. running=.0  else.
     d=.b-a
     good=.q+d<:#Subject
      if. good  do.
       for_j. i.d  do.
        if. -.((a+j){Subject) char_equal (q+j){Subject  do. good=.0
   break.  end.
       end.
      end.
      if. good  do. q=.q+d
  p=.p+1
   if. d>0  do. visited=.i.0  end.   else. running=.0  end.
     end.
    case. 'LOOK'  do.
    'mode target'=.arg
    result=.bt_execute (p+1);q;cap;1
     if. mode-:'NOT'  do.
      if. 0=#result  do. p=.target  else. running=.0  end.
     elseif. 0=#result  do. running=.0
     else.
     'cap q1'=.result
      if. mode-:'ATOMIC'  do.  if. q1>q  do. visited=.i.0  end.
  q=.q1  end.
     p=.target
     end.
    case. 'MATCH'  do.
     if. partial+.( -.FullMatch)+.q=#Subject  do. cap;q  return.  else. running=.0  end.
    end.
   end.
  end.
 0$a:
)
bt_search=:3 :0
  if. FullMatch  do. starts=.,0  else. starts=.y+i.(1+#Subject)-y  end.
  for_b. starts  do.
  r=.bt_execute 0;b;((2*Groups+1)$ _1);0
   if. #r  do. 0{::r  return.  end.
  end.
 i.0
)
