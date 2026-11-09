pike_add=:4 :0
 'threads marks'=.x
 'p cap q'=.y
 pending=.,<p;cap
  while. #pending  do.
  'pc c'=.>{:pending
  pending=.}:pending
   if. pc e.marks  do.  continue.  end.
  marks=.marks,pc
  PikeSteps=:PikeSteps+1
  'op arg'=.pc{::Code
   select. op
   case. 'JMP'  do. pending=.pending,<arg;c
   case. 'SPLIT'  do. pending=.pending,(<(1{arg);c),<((0{arg);c)
   case. 'SAVE'  do. pending=.pending,<(pc+1);(q arg}c)
   case. 'ASSERT'  do.  if. arg assertion q  do. pending=.pending,<(pc+1);c  end.
   case.  do. threads=.threads,<pc;c
   end.
  end.
 threads;marks
)
pike_search=:3 :0
 q=.y
 list=.(0$a:);i.0
 best=.i.0
  while. q<:#Subject  do.
   if. (0=#best)*.((-.FullMatch)+.q=y)  do. list=.list pike_add 0;((2*Groups+1)$ _1);q  end.
  next=.(0$a:);i.0
   for_thread. 0{::list  do.
   'p cap'=.>thread
   PikeSteps=:PikeSteps+1
   ins=.p{::Code
    if. 'MATCH'-:0{::ins  do.
     if. ( -.FullMatch)+.q=#Subject  do. best=.cap
   break.  end.
    elseif. ins consumes q  do. next=.next pike_add (p+1);cap;q+1  end.
   end.
   if. q=#Subject  do.  break.  end.
   if. 0=#0{::next  do.  if. (#best)+.FullMatch  do.  break.  end.  end.
  list=.next
  q=.q+1
  end.
 best
)
