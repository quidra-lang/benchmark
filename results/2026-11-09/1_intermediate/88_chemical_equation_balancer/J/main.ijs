words=:3 : '(<;._1 '' '',y)-.<'''''
LF=:10{a.
Upper=:'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
Lower=:'abcdefghijklmnopqrstuvwxyz'
Digits=:'0123456789'
Elements=:words 'H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe'
Weights=:1008 4003 6941 9012 10811 12011 14007 15999 18998 20180 22990 24305 26982 28086 30974 32065 35453 39948 39098 40078 44956 47867 50942 51996 54938 55845 58933 58693 63546 65380 69723 72630 74922 78971 79904 83798 85468 87620 88906 91224 92906 95950 98000 101070 102906 106420 107868 112414 114818 118710 121760 127600 126904 131293x
num=:3 : ',''0'' 8!:2 y'
join=:4 : 0
 r=.''
 for_i. i.#y do. if. i do. r=.r,x end. r=.r,i{::y end.
 r
)
nums=:3 : ''' ''join num each y'
fail=:3 : 0
 Error=:y
 throw.
)
fixed=:4 : 0
 h=.|y
 unit=.10x^x
 s=.num unit|h
 r=.(num <.h%unit),'.',((x-#s)$'0'),s
 if. y<0 do. r=.'-',r end.
 r
)
signed=:3 : 'if. y>0 do. ''+'',num y else. num y end.'
rational=:3 : 0
 'p q'=.2 x:y
 r=.signed p
 if. q~:1 do. r=.r,'/',num q end.
 r
)
hillorder=:3 : 0
 ids=.I.y>0
 ids=.( /:ids{Elements){ids
 if. 5 e.ids do.
  front=.5
  if. 0 e.ids do. front=.front,0 end.
  ids=.front,ids-.front
 end.
 ids
)
hill=:3 : 0
 r=.''
 for_i. hillorder y do.
  r=.r,i{::Elements
  if. (i{y)~:1 do. r=.r,num i{y end.
 end.
 r
)
charged=:3 : 0
 'comp q'=.y
 r=.hill comp
 if. q do.
  r=.r,'^'
  if. 1<|q do. r=.r,num |q end.
  r=.r,(q<0){'+-'
 end.
 r
)
invalid=:3 : 'fail ''invalid formula '',Original'
peek=:3 : 'if. Pos<#Formula do. Pos{Formula else. '' '' end.'
count=:3 : 0
 if. -. (peek'')e.Digits do. 1x return. end.
 if. '0'=peek'' do. invalid'' end.
 start=.Pos
 while. (peek'')e.Digits do. Pos=:Pos+1 end.
 x:0".(Pos-start){.start}.Formula
)
sequence=:3 : 0
 comp=.54$0x
 seen=.0
 while. 1 do.
  c=.peek''
  if. c e.Upper do.
   sym=.,c
   Pos=:Pos+1
   if. (peek'')e.Lower do. sym=.sym,peek''
    Pos=:Pos+1
   end.
   i=.Elements i.<sym
   item=.54$0x
   if. i=54 do. if. 0=#Unknown do. Unknown=:sym end.
   else. item=.1x i}item end.
  elseif. c e.'([' do.
   Pos=:Pos+1
   item=.sequence''
   closing=.('(['i.c){')]'
   if. closing~:peek'' do. invalid'' end.
   Pos=:Pos+1
  else. break. end.
  n=.count''
  comp=.comp+n*item
  seen=.1
 end.
 if. -.seen do. invalid'' end.
 comp
)
formula=:4 : 0
 Original=:x
 Formula=:y
 Pos=:0
 Unknown=:''
 comp=.sequence''
 while. '.'=peek'' do.
  Pos=:Pos+1
  n=.count''
  part=.sequence''
  comp=.comp+n*part
 end.
 q=.0x
 if. '^'=peek'' do.
  Pos=:Pos+1
  q=.count''
  c=.peek''
  if. -.c e.'+-' do. invalid'' end.
  if. c='-' do. q=.-q end.
  Pos=:Pos+1
 end.
 if. Pos~:#Formula do. invalid'' end.
 if. #Unknown do. fail 'unknown element ',Unknown end.
 comp;q
)
species=:4 : 0
 word=.y
 core=.y
 state=.''
 for_s. words '(s) (l) (g) (aq)' do.
  if. (>s)-:(-#>s){.core do. state=.>s
   core=.(-#state)}.core
   break.
  end.
 end.
 coef=.1x
 offset=.0
 if. x do.
  if. #core do.
   if. ({.core)e.Digits do.
    if. '0'={.core do. fail 'invalid formula ',word end.
    while. offset<#core do. if. -. (offset{core)e.Digits do. break. end. offset=.offset+1 end.
    coef=.x:0".offset{.core
    core=.offset}.core
   end.
  end.
 end.
 'comp charge'=.word formula core
 (offset}.word);core;state;comp;charge;coef
)
mass=:3 : '+/Weights*3{::y'
equation=:4 : 0
 n=.#y
 good=.(n>:3)*.1=2|n
 if. good do.
  odds=.(2*i.>.n%2){y
  evens=.(1+2*i.<.n%2){y
  good=.(-.+./odds e.words '+ ->')*.(*./evens e.words '+ ->')*.1=+/evens=<'->'
 end.
 if. -.good do. fail 'malformed equation' end.
 left=.>. (y i.<'->')%2
 list=.0$a:
 for_s. odds do. list=.list,<x species >s end.
 left;<list
)
compositions=:3 : 0
 r=.0 55$0x
 for_s. y do. r=.r,(3{::>s),4{::>s end.
 |:r
)
matrix=:4 : 0
 a=.compositions y
 used=.hillorder +/"1 |54{.a
 labels=.(used{Elements),<'charge'
 a=.(used,54){a
 (a*"1 x);<labels
)
nullspace=:3 : 0
 a=.x:y
 'm n'=.$a
 r=.0
 piv=.i.0
 free=.i.0
 for_j. i.n do.
  candidates=.r+I.0~:j{"1 r}.a
  if. 0=#candidates do. free=.free,j continue. end.
  i=.{.candidates
  if. i~:r do. a=.((i,r){a)(r,i)}a end.
  row=.r{a
  row=.row%j{row
  a=.row r}a
  for_i. (i.m)-.r do.
   rowi=.i{a
   a=.(rowi-(j{rowi)*row)i}a
  end.
  piv=.piv,j
  r=.r+1
 end.
 basis=.0$a:
 for_f. free do.
  v=.n$0x
  v=.1x f}v
  for_k. i.#piv do. v=.(-(<k,f){a)(k{piv)}v end.
  den=.1x
  for_z. v do. den=.den*.1{2 x:z end.
  v=.den*v
  g=.+./|v
  basis=.basis,<v%g
 end.
 r;<basis
)
coefficients=:4 : 0
 'a labels'=.y
 'rank basis'=.nullspace a
 if. 0=#basis do. 'IMPOSSIBLE' return. end.
 if. 1<#basis do. 'AMBIGUOUS (nullity ',(num #basis),')' return. end.
 v=.>{.basis
 if. 0>{.v do. v=.-v end.
 if. +./0>:x{.v do. 'IMPOSSIBLE' else. v end.
)
term=:4 : 'if. x=1 do. y else. (num x),y end.'
notation=:3 : 0
 'list coefs left original'=.y
 lhs=.0$a:
 rhs=.0$a:
 for_i. i.original do.
  t=.(i{coefs)term 0{::i{::list
  if. i<left do. lhs=.lhs,<t else. rhs=.rhs,<t end.
 end.
 for_i. original+i.(#list)-original do.
  c=.i{coefs
  t=.(|c)term 0{::i{::list
  if. c>0 do. lhs=.lhs,<t elseif. c<0 do. rhs=.rhs,<t end.
 end.
 (' + 'join lhs),' -> ',' + 'join rhs
)
decimal=:4 : 0
 'places maxdigits signedAllowed'=.x
 s=.y
 sign=.1x
 if. signedAllowed do.
  if. #s do. if. '-'={.s do. sign=._1x
   s=.}.s
  end. end.
 end.
 ps=.<;._1 '.',s
 if. -. (#ps)e.1 2 do. _ return. end.
 whole=.0{::ps
 if. (0=#whole)+.maxdigits<#whole do. _ return. end.
 if. -.*./whole e.Digits do. _ return. end.
 if. (1<#whole)*.'0'={.whole do. _ return. end.
 frac=.''
 if. 2=#ps do.
  frac=.1{::ps
  if. (0=#frac)+.places<#frac do. _ return. end.
  if. -.*./frac e.Digits do. _ return. end.
 end.
 frac=.frac,((places-#frac)$'0')
 sign*(x:0".whole,frac)
)
quantity=:3 : 0
 q=.3 4 0 decimal y
 if. (q=_)+.q<:0 do. fail 'invalid quantity ',y end.
 q
)
heatvalue=:3 : 0
 h=.2 5 1 decimal y
 if. h=_ do. fail 'invalid enthalpy ',y end.
 h
)
ratio=:3 : 0
 ids=.hillorder y
 a=.ids{y
 w=.ids{Weights
 proportions=.a%w
 rho=.proportions%<./proportions
 out=.0$a:
 for_i. i.#ids do. out=.out,<((i{ids){::Elements),' ',3 fixed <.1000*i{rho end.
 for_k. 1+i.12 do.
  v=.k*rho
  nearest=.<.v+1r2
  if. *./(|v-nearest)<:1r20 do.
   comp=.nearest ids}54$0x
   out=.out,<(hill comp),' (k = ',(num k),')'
   out return.
  end.
 end.
 out,<'no simple ratio'
)
saltpart=:4 : 0
 core=.(y i.'^'){.y
 if. x=1 do. core return. end.
 direct=.(<core)e.Elements
 if. '['={.core do.
  depth=.0
  for_i. i.#core do.
   c=.i{core
   if. c='[' do. depth=.depth+1 elseif. c=']' do. depth=.depth-1 end.
   if. depth=0 do. direct=.i=(#core)-1 break. end.
  end.
 end.
 if. direct do. core,num x else. '(',core,')',num x end.
)
oxidation=:3 : 0
 'comp q'=.y
 ids=.hillorder comp
 xs=.54$0x
 assigned=.i.0
 if. 1=#ids do. xs=.(q%({.ids){comp)({.ids)}xs
 else.
  if. 8 e.ids do. xs=._1x 8}xs
   assigned=.assigned,8
  end.
  metals=.Elements i.words 'Li Na K Rb Be Mg Ca Sr Al'
  for_i. ids do.
   k=.metals i.i
   if. k<9 do.
    z=.1+(k>:4)+(k=8)
    xs=.z i}xs
    assigned=.assigned,i
   end.
  end.
  if. 0 e.ids do.
   z=.1x
   if. *./(ids-.0)e.metals do. z=._1x end.
   xs=.z 0}xs
   assigned=.assigned,0
  end.
  if. 7 e.ids do. xs=._2x 7}xs
   assigned=.assigned,7
  end.
  if. -. +./7 8 e.ids do.
   for_i. 16 34 52 do. if. i e.ids do. xs=._1x i}xs
    assigned=.assigned,i
    break.
   end. end.
  end.
  unknown=.ids-.assigned
  if. 1<#unknown do. 'indeterminate: ',' 'join unknown{Elements return. end.
  total=.+/comp*xs
  if. 1=#unknown do. i=.{.unknown
   xs=.((q-total)%i{comp)i}xs
  elseif. total~:q do. i=.{:assigned
   xs=.((i{xs)+(q-total)%i{comp)i}xs
  end.
 end.
 ss=.0$a:
 for_i. ids do. ss=.ss,<(i{::Elements),' ',rational i{xs end.
 ', 'join ss
)
Commands=:words 'ELEMENT PARSE MASS PERCENT EMPIRICAL DBE OXSTATE MOLES GRAMS MOLECULAR SALT DERIVE COMBUST BALANCE MATRIX CHECK REDOX HALF STOICH LIMITING YIELD HEAT DELTAH HEATS'
HeatNames=:0$a:
Heats=:0$0x
command=:3 : 0
 ws=.words y
 cmd=.>{.ws
 args=.}.ws
 n=.#args
 if. -. (<cmd)e.Commands do. fail 'unknown command ',cmd end.
 good=.1
 if. (<cmd)e.words 'ELEMENT PARSE MASS PERCENT EMPIRICAL DBE OXSTATE' do. good=.n=1
 elseif. (<cmd)e.words 'MOLES GRAMS MOLECULAR SALT HEAT' do. good=.n=2
 elseif. cmd-:'COMBUST' do. good=.n=3
 elseif. cmd-:'HEATS' do. good=.n=0
 elseif. cmd-:'DERIVE' do. good=.(n>:2)*.0=2|n
 elseif. (<cmd)e.words 'BALANCE MATRIX CHECK DELTAH' do. good=.n>:1
 elseif. (<cmd)e.words 'REDOX HALF' do. good=.n>:2 end.
 if. -.good do. fail 'wrong argument count for ',cmd end.
 out=.0$a:
 if. cmd-:'ELEMENT' do.
  sym=.0{::args
  i=.Elements i.<sym
  if. i=54 do. fail 'unknown element ',sym end.
  ,<sym,' (Z = ',(num i+1),') ',(3 fixed i{Weights),' u' return.
 end.
 if. cmd-:'HEATS' do.
  if. 0=#HeatNames do. ,<'no enthalpies' return. end.
  for_i. /:HeatNames do. out=.out,<(i{::HeatNames),' ',(2 fixed i{Heats),' kJ/mol' end.
  out return.
 end.
 if. cmd-:'HEAT' do.
  s=.0 species 0{::args
  h=.heatvalue 1{::args
  name=.0{::s
  i=.HeatNames i.<name
  line=.'dHf(',name,') = ',(2 fixed h),' kJ/mol'
  if. i<#HeatNames do. line=.line,' (was ',(2 fixed i{Heats),')'
   Heats=:h i}Heats
  else. HeatNames=:HeatNames,<name
   Heats=:Heats,h
  end.
  ,<line return.
 end.
 if. (<cmd)e.words 'PARSE MASS PERCENT EMPIRICAL DBE OXSTATE MOLES GRAMS MOLECULAR SALT' do.
  f=.0{::args
  'comp charge'=.f formula f
  m=.+/comp*Weights
  ids=.hillorder comp
  select. cmd
  case. 'PARSE' do.
   ss=.0$a:
   for_i. ids do. ss=.ss,<(i{::Elements),' ',num i{comp end.
   ,<(charged comp;charge),' (',(', 'join ss),'; charge ',(signed charge),')'
  case. 'MASS' do. ,<'M(',f,') = ',(3 fixed m),' g/mol'
  case. 'PERCENT' do.
   for_i. ids do. out=.out,<(i{::Elements),' ',(2 fixed <.(10000*(i{comp)*i{Weights)%m),'%' end.
   out
  case. 'EMPIRICAL' do.
   g=.+./ids{comp
   ,<(hill comp%g),' (n = ',(num g),')'
  case. 'DBE' do.
   if. charge do. fail 'charged formula ',f end.
   names=.Elements i.words 'H F Cl Br I O S Se B N P As C Si Ge'
   vals=.1 1 1 1 1 2 2 2 3 3 3 3 4 4 4
   t=.2x
   for_i. ids do.
    k=.names i.i
    if. k=#names do. fail 'no valence for ',i{::Elements end.
    t=.t+(i{comp)*(_2+k{vals)
   end.
   ,<'DBE = ',1 fixed 5*t
  case. 'OXSTATE' do. ,<oxidation comp;charge
  case. 'MOLES';'GRAMS';'MOLECULAR' do.
   if. (cmd-:'MOLECULAR')*.charge~:0 do. fail 'charged formula ',f end.
   q=.quantity 1{::args
   if. cmd-:'MOLES' do. ,<(3 fixed q),' g ',f,' = ',(6 fixed <.(q*1000000)%m),' mol'
   elseif. cmd-:'GRAMS' do. ,<(3 fixed q),' mol ',f,' = ',(3 fixed <.(q*m)%1000),' g'
   else.
    k=.<.(2*q)+m
    k=.<.k%2*m
    if. (k=0)+.(10*|q-k*m)>m do. ,<'no integer multiple (ratio ',(3 fixed <.(1000*q)%m),')'
    else. ,<(hill k*comp),' (n = ',(num k),', ',(3 fixed k*m),' g/mol)' end.
   end.
  case. 'SALT' do.
   f2=.1{::args
   'comp2 charge2'=.f2 formula f2
   if. charge<:0 do. fail 'not a cation ',f end.
   if. charge2>:0 do. fail 'not an anion ',f2 end.
   if. '.'e.f do. fail 'hydrate ion ',f end.
   if. '.'e.f2 do. fail 'hydrate ion ',f2 end.
   g=.charge+.|charge2
   a=.(|charge2)%g
   b=.charge%g
   comp=.(a*comp)+b*comp2
   ,<(a saltpart f),(b saltpart f2),' (',(hill comp),', ',(3 fixed +/Weights*comp),' g/mol)'
  end.
  return.
 end.
 if. cmd-:'DERIVE' do.
  amounts=.54$0x
  seen=.i.0
  for_j. i.n%2 do.
   sym=.(2*j){::args
   qword=.(1+2*j){::args
   i=.Elements i.<sym
   if. i=54 do. fail 'unknown element ',sym end.
   if. i e.seen do. fail 'duplicate element ',sym end.
   q=.quantity qword
   if. q>100000 do. fail 'invalid percentage ',qword end.
   amounts=.q i}amounts
   seen=.seen,i
  end.
  total=.+/amounts
  if. (|total-100000)>1000 do. fail 'percentages sum to ',3 fixed total end.
  ratio amounts return.
 end.
 if. cmd-:'COMBUST' do.
  s=.quantity 0{::args
  p=.quantity 1{::args
  r=.quantity 2{::args
  c=.<.(p*12011)%44009
  h=.<.(r*2016)%18015
  o=.s-c+h
  if. (c=0)+.(h=0)+.(100*o)<-s do. fail 'inconsistent masses' end.
  ids=.5 0
  amounts=.(c,h)ids}54$0x
  if. (100*o)>s do. ids=.ids,7
   amounts=.o 7}amounts
  end.
  for_i. ids do. out=.out,<'mass ',(i{::Elements),' ',(3 fixed i{amounts),' g' end.
  out,ratio amounts return.
 end.
 eq=.args
 if. (<cmd)e.words 'STOICH LIMITING YIELD' do.
  if. 1~:+/args=<':' do. fail 'invalid separator' end.
  at=.args i.<':'
  eq=.at{.args
  tail=.(at+1)}.args
  if. (cmd-:'STOICH')*.2~:#tail do. fail 'wrong argument count for STOICH' end.
  if. (cmd-:'YIELD')*.4~:#tail do. fail 'wrong argument count for YIELD' end.
 end.
 if. (<cmd)e.words 'REDOX HALF' do.
  medium=.0{::args
  if. -. (<medium)e.words 'acidic basic' do. fail 'invalid medium ',medium end.
  eq=.}.args
 end.
 'left list'=.(cmd-:'CHECK')equation eq
 original=.#list
 names=.0$a:
 masses=.0$0x
 for_s. list do. names=.names,<0{::>s
  masses=.masses,mass >s
 end.
 if. cmd-:'STOICH' do.
  s=.0{::tail
  chosen=.names i.<s
  if. chosen=#names do. fail 'species ',s,' not in equation' end.
  q=.quantity 1{::tail
 elseif. cmd-:'LIMITING' do.
  if. left~:#tail do. fail 'expected ',(num left),' masses, got ',num #tail end.
  qs=.0$0x
  for_t. tail do. qs=.qs,quantity >t end.
 elseif. cmd-:'YIELD' do.
  s1=.0{::tail
  s2=.2{::tail
  a=.(left{.names)i.<s1
  if. a=left do. fail s1,' is not a reactant' end.
  b=.left+(left}.names)i.<s2
  if. b=#names do. fail s2,' is not a product' end.
  q1=.quantity 1{::tail
  q2=.quantity 3{::tail
 elseif. cmd-:'DELTAH' do.
  for_s. names do. if. -.s e.HeatNames do. fail 'no enthalpy for ',>s end. end.
 end.
 signs=.(left$1x),((original-left)$_1x)
 if. (<cmd)e.words 'REDOX HALF' do.
  for_s. list do. if. (<1{::>s)e.words 'H^+ OH^- H2O' do. fail 'reserved species ',0{::>s end. end.
  aux=.'H^+'
  if. medium-:'basic' do. aux=.'OH^- ' end.
  aux=.deb aux
  list=.list,(<0 species aux),<0 species 'H2O'
  signs=.signs,1 1
  if. cmd-:'HALF' do. list=.list,<'e^-';'e^-';'';(54$0x);_1x;1x
   signs=.signs,1
  end.
 end.
 'mat labels'=.signs matrix list
 if. cmd-:'MATRIX' do.
  'rank basis'=.nullspace mat
  out=.,<'columns: ',' 'join names
  for_i. i.#labels do. out=.out,<(i{::labels),': ',nums i{mat end.
  out=.out,<'rank ',(num rank),', nullity ',num #basis
  for_v. basis do. out=.out,<'null: ',nums >v end.
  out return.
 end.
 if. cmd-:'CHECK' do.
  coeff=.0$0x
  for_s. list do. coeff=.coeff,5{::>s end.
  totals=.mat*"1 coeff
  lhs=.+/"1 left{."1 totals
  rhs=.-+/"1 left}."1 totals
  diff=.I.lhs~:rhs
  if. #diff do.
   out=.,<'not balanced'
   for_i. diff do.
    if. i=(#labels)-1 do. l=.signed i{lhs
     r=.signed i{rhs
    else. l=.num i{lhs
     r=.num i{rhs
    end.
    out=.out,<(i{::labels),': ',l,' != ',r
   end.
  else.
   g=.+./coeff
   if. g=1 do. out=.,<'balanced' else. out=.,<'balanced, not in lowest terms (gcd ',(num g),')' end.
  end.
  out return.
 end.
 coeff=.original coefficients mat;<labels
 if. 2=3!:0 coeff do. ,<coeff return. end.
 line=.notation list;coeff;left;original
 out=.,<line
 select. cmd
 case. 'BALANCE';'REDOX' do. out
 case. 'HALF' do.
  c=.{:coeff
  if. c>0 do. word=.'reduction' elseif. c<0 do. word=.'oxidation' else. word=.'no electron transfer' end.
  out,<word
 case. 'STOICH' do.
  d=.(chosen{coeff)*chosen{masses
  for_i. i.original do.
   c=.i{coeff
   s=.(i{::names),' ',(6 fixed <.(q*c*1000000)%d),' mol ',(3 fixed <.(q*c*i{masses)%d),' g'
   if. '(g)'-:2{::i{::list do. s=.s,' ',(3 fixed <.(q*c*22414)%d),' L' end.
   out=.out,<s
  end.
  out
 case. 'LIMITING' do.
  ratios=.qs%(left{.coeff)*left{.masses
  l=.ratios i.<./ratios
  q=.l{qs
  d=.(l{coeff)*l{masses
  out=.out,<'limiting ',l{::names
  out=.out,<'extent ',(6 fixed <.(q*1000000)%d),' mol'
  for_i. left+i.original-left do.
   c=.i{coeff
   s=.'product ',(i{::names),' ',(3 fixed <.(q*c*i{masses)%d),' g'
   if. '(g)'-:2{::i{::list do. s=.s,' ',(3 fixed <.(q*c*22414)%d),' L' end.
   out=.out,<s
  end.
  for_i. (i.left)-.l do.
   h=.<.((i{qs)*d)-(q*(i{coeff)*i{masses)
   h=.<.h%d
   out=.out,<'remaining ',(i{::names),' ',(3 fixed h),' g'
  end.
  out
 case. 'YIELD' do.
  t=.<.(q1*(b{coeff)*b{masses)%((a{coeff)*a{masses)
  out=.out,<'theoretical ',(3 fixed t),' g'
  out=.out,<'actual ',(3 fixed q2),' g'
  if. t=0 do. out,<'yield undefined' else. out,<'yield ',(2 fixed <.(q2*10000)%t),'%' end.
 case. 'DELTAH' do.
  h=.-+/signs*coeff*(HeatNames i.names){Heats
  if. h<0 do. word=.'exothermic' elseif. h>0 do. word=.'endothermic' else. word=.'thermoneutral' end.
  out,<'dH = ',(2 fixed h),' kJ (',word,')'
 end.
)
main=:3 : 0
 lines=.<;._2 (1!:1&3''),LF
 n=.0".>{.lines
 for_line. n{.}.lines do.
  try. out=.command >line
  catcht. out=.,<'error: ',Error end.
  for_s. out do. 1!:2&2 (>s),LF end.
 end.
)
main''
