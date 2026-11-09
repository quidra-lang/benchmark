builtin_error=:3 :0
 Ball=:CurrentPI exception y
 13!:8]3
)
check_integer=:3 :0
 t=.deref y
  if. kind__t=0  do. builtin_error atom 'instantiation_error' end.
  if. kind__t~:1  do. builtin_error 'integer' type_error t  end.
 value__t
)
check_atom=:3 :0
 t=.deref y
  if. kind__t=0  do. builtin_error atom 'instantiation_error' end.
  if. kind__t~:2  do. builtin_error 'atom' type_error t  end.
 value__t
)
check_list=:3 :0
 'es tail'=.unlist y
  if. kind__tail=0  do. builtin_error atom 'instantiation_error' end.
  if. -.(kind__tail=2)*.value__tail-:'[]' do. builtin_error 'list' type_error y  end.
 es
)
arithmetic=:3 :0
 t=.deref y
  if. kind__t=0  do. builtin_error atom 'instantiation_error' end.
  if. kind__t=1  do. value__t  return.  end.
 pi=.key t
 supported=:'+/2';'-/2';'*/2';'///2';'mod/2';'rem/2';'-/1';'abs/1';'min/2';'max/2'
  if. -.(<pi)e.supported  do. builtin_error 'evaluable' type_error indicator_term indicator t  end.
 a=.arithmetic 0{args__t
  if. 1=#args__t  do.  if. value__t-:'-' do. r=.-a  else. r=.|a  end.
  else.
  b=.arithmetic 1{args__t
   if. (<value__t)e.'//';'mod';'rem' do.  if. b=0  do. builtin_error 'evaluation_error' compound ,atom 'zero_divisor' end.  end.
   select. value__t
   case. '+' do. r=.a+b
   case. '-' do. r=.a-b
   case. '*' do. r=.a*b
   case. '//' do. r=.(*a%b)*<.|a%b
   case. 'mod' do. r=.a-b*<.a%b
   case. 'rem' do. r=.a-b*(*a%b)*<.|a%b
   case. 'min' do. r=.a<.b
   case. 'max' do. r=.a>.b
   end.
  end.
  if. (r<_2147483648)+.r>2147483647  do. builtin_error 'evaluation_error' compound ,atom 'int_overflow' end.
 r
)
deterministic=:3 :0
 g=.y
 pi=.key g
 es=.args__g
  if. #es  do. a=.deref 0{es  end.
  if. 1<#es  do. b=.deref 1{es  end.
  if. 2<#es  do. c=.deref 2{es  end.
  select. pi
  case. 'true/0' do. 1
  case. 'fail/0';'false/0' do. 0
  case. '=/2' do. a unify b
  case. '\=/2' do. mark=.#Trail
  ok=.a unify b
  undo mark
  -.ok
  case. '==/2' do. a identical b
  case. '\==/2' do. -.a identical b
  case. 'var/1' do. kind__a=0
  case. 'nonvar/1' do. kind__a~:0
  case. 'atom/1' do. kind__a=2
  case. 'number/1';'integer/1' do. kind__a=1
  case. 'atomic/1' do. kind__a e.1 2
  case. 'compound/1' do. kind__a=3
  case. 'callable/1' do. kind__a e.2 3
  case. 'is_list/1' do. 'xs tail'=.unlist a
  (kind__tail=2)*.value__tail-:'[]'
  case. 'is/2' do. a unify integer arithmetic b
  case. '=:=/2';'=\=/2';'</2';'>/2';'=</2';'>=/2' do.
  x=.arithmetic a
  y=.arithmetic b
   select. pi
   case. '=:=/2' do. x=y
   case. '=\=/2' do. x~:y
   case. '</2' do. x<y
   case. '>/2' do. x>y
   case. '=</2' do. x<:y
   case. '>=/2' do. x>:y
   end.
  case. 'functor/3' do.
   if. kind__a~:0  do.
    if. kind__a=3  do. n=.atom value__a
  ar=.#args__a  else. n=.a
  ar=.0 end.
    if. -.b unify n  do. 0  return.  end.
   c unify integer ar
   else.
    if. (kind__b=0)+.kind__c=0  do. builtin_error atom 'instantiation_error' end.
    if. kind__b=3  do. builtin_error 'atomic' type_error b  end.
    if. kind__c~:1  do. builtin_error 'integer' type_error c  end.
   ar=.value__c
    if. ar<0  do. builtin_error 'not_less_than_zero' domain_error c  end.
    if. ar>255  do. builtin_error 'representation_error' compound ,atom 'max_arity' end.
    if. ar=0  do. a unify b  return.  end.
    if. kind__b=1  do. builtin_error 'atom' type_error b  end.
   xs=.0$a:
    for_i. i.ar  do. xs=.xs,fresh'' end.
   a unify value__b compound xs
   end.
  case. 'arg/3' do.
   if. (kind__a=0)+.kind__b=0  do. builtin_error atom 'instantiation_error' end.
   if. kind__a~:1  do. builtin_error 'integer' type_error a  end.
   if. kind__b~:3  do. builtin_error 'compound' type_error b  end.
   if. (value__a<1)+.value__a>#args__b  do. 0 else. c unify (value__a-1){args__b  end.
  case. '=../2' do.
   if. kind__a~:0  do.
    if. kind__a=3  do. xs=.(atom value__a),args__a  else. xs=.,a  end.
   b unify proper_list xs
   else.
   xs=.check_list b
    if. 0=#xs  do. builtin_error 'non_empty_list' domain_error atom '[]' end.
   h=.deref {.xs
    if. kind__h=0  do. builtin_error atom 'instantiation_error' end.
    if. 1=#xs  do.
     if. kind__h=3  do. builtin_error 'atomic' type_error h  end.
    a unify h
    else.
     if. kind__h~:2  do. builtin_error 'atom' type_error h  end.
     if. (#xs)>256  do. builtin_error 'representation_error' compound ,atom 'max_arity' end.
    a unify value__h compound }.xs
    end.
   end.
  case. 'copy_term/2' do. b unify copy_term a
  case. 'atom_length/2' do.
  n=.#check_atom a
   if. -.kind__b e.0 1 do. builtin_error 'integer' type_error b  end.
  b unify integer n
  case. 'atom_chars/2' do.
   if. kind__a~:0 do.
   s=.check_atom a
  xs=.0$a:
    for_ch. s  do. xs=.xs,atom ,ch  end.
   b unify proper_list xs
   else.
   xs=.check_list b
  s=.''
    for_ch. xs  do.
    t=.deref ch
     if. kind__t=0  do. builtin_error atom 'instantiation_error' end.
     if. (kind__t~:2)+.1~:#value__t  do. builtin_error 'character' type_error t  end.
    s=.s,value__t
    end.
   a unify atom s
   end.
  case. 'write/1';'writeq/1' do.
  NameVars=:0$a:
  Names=:0$a:
  NameCounter=:0
  Quoted=:pi-:'writeq/1'
  QueryOutput=:QueryOutput,(1200;0)write_term a
  1
  case. 'nl/0' do. QueryOutput=:QueryOutput,LF
  1
  end.
)
