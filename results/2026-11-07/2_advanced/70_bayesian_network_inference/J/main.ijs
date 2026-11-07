ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'network_io.ijs'
load SourceDirectory,'learning.ijs'
load SourceDirectory,'factors.ijs'
load SourceDirectory,'elimination.ijs'
load SourceDirectory,'sampling.ijs'
str =: 3 : 0
 if. 2=3!:0 y do. y return. end.
 n =. <.|y
 text =. ''
 while. n>0 do.
  text =. ((10|n){'0123456789'),text
  n =. <.n%10
 end.
 if. 0=#text do. text =. '0' end.
 if. y<0 do. '-',text else. text end.
)
join =: 4 : 0
 t =. ''
 for_i. i.#y do.
  if. i do. t =. t,x end.
  t =. t,str i{::y
 end.
 t
)
emit =: 3 : ''' ''join y'
fixed =: 3 : 0
 n =. <.0.5+10000*|y
 t =. (str <.n%10000),'.',_4{.'0000',str 10000|n
 if. (y<0)*.n do. '-',t else. t end.
)
write =: 4 : 0
 (;(,&LF)&.>y)1!:2 <'output/',x
 i.0 0
)
names =: 3 : 0
 if. #y do. ' 'join y{VNames else. '-' end.
)
ancestors =: 3 : 0
 a =. /:~~.y
 while. 1 do.
  b =. a
  for_v. a do. b =. ~.b,v{::Parents end.
  b =. /:~b
  if. b-:a do. b return. end.
  a =. b
 end.
)
closure_children =: 3 : 0
 a =. /:~~.y
 while. 1 do.
  b =. a
  for_v. a do. b =. ~.b,v{::Children end.
  b =. /:~b
  if. b-:a do. b return. end.
  a =. b
 end.
)
blanket =: 3 : 0
 a =. (y{::Parents),y{::Children
 for_c. y{::Children do. a =. a,c{::Parents end.
 /:~~.a-.y
)
structure =: 3 : 0
 Children =: NV$<i.0
 for_v. i.NV do.
  for_p. v{::Parents do. Children =: (<(p{::Children),v)p}Children end.
 end.
 Topological =: i.0
 Depth =: NV$0
 while. (#Topological)<NV do.
  for_v. (i.NV)-.Topological do.
   ps =. v{::Parents
   if. *./ps e.Topological do.
    d =. 0
    if. #ps do. d =. 1+>./ps{Depth end.
    Depth =: d v}Depth
    Topological =: Topological,v
    break.
   end.
  end.
 end.
 i.0 0
)
evidence =: 3 : 0
 ev =. es =. i.0
 for_f. y do.
  'v s' =. <;._1 '=',>f
  i =. VNames i.<v
  ev =. ev,i
  es =. es,(i{::States)i.<s
 end.
 ev;es
)
assignment_text =: 4 : 0
 a =. 0$a:
 for_v. x do. a =. a,<(v{::VNames),'=',(v{y){::v{::States end.
 if. #a do. ' 'join a else. '-' end.
)
marginals =: 3 : 0
 'scope values' =. y
 out =. NV$<i.0
 for_v. scope do. out =. (<(v{K)$0.0)v}out end.
 a =. assignments scope
 for_i. i.#a do.
  row =. i{a
  for_j. i.#scope do.
   v =. j{scope
   s =. j{row
   vals =. v{::out
   vals =. ((s{vals)+i{values)s}vals
   out =. (<vals)v}out
  end.
 end.
 out
)
distribution_lines =: 4 : 0
 'q marginal' =. y
 out =. 0$a:
 for_v. q do.
  line =. x,' ',v{::VNames
  for_s. i.v{K do. line =. line,' ',(s{::v{::States),' ',fixed s{v{::marginal end.
  out =. out,<line
 end.
 out
)
bayes_ball =: 3 : 0
 'xs zs' =. y
 az =. ancestors zs
 queue =. xs,.0*xs
 seen =. (NV,2)$0
 i =. 0
 while. i<#queue do.
  'v direction' =. i{queue
  i =. i+1
  if. (<v,direction){seen do. continue. end.
  seen =. 1(<v,direction)}seen
  if. direction=0 do.
   if. -.v e.zs do.
    ps =. v{::Parents
    cs =. v{::Children
    queue =. queue,(ps,.0*ps),cs,.1+0*cs
   end.
  else.
   if. -.v e.zs do. cs =. v{::Children
   queue =. queue,cs,.1+0*cs end.
   if. v e.az do. ps =. v{::Parents
   queue =. queue,ps,.0*ps end.
  end.
 end.
 (I.+./"1 seen)-.zs,xs
)
path =: 3 : 0
 'a b ignorex ignorey' =. y
 prev =. NV$_1
 prev =. a a}prev
 queue =. ,a
 head =. 0
 while. head<#queue do.
  v =. head{queue
  head =. head+1
  for_c. v{::Children do.
   if. (v=ignorex)*.c=ignorey do. continue. end.
   if. (c{prev)>:_0 do. continue. end.
   prev =. v c}prev
   if. c=b do.
    route =. ,b
    while. ({.route)~:a do. route =. (({.route){prev),route end.
    route return.
   end.
   queue =. queue,c
  end.
 end.
 i.0
)
plan_report =: 4 : 0
 out =. <'order ',x
 sizes =. i.0
 for_rec. y do.
  'v fill scope entries' =. >rec
  sizes =. sizes,entries
  out =. out,<emit 'step';(v{::VNames);'fill';fill;'scope';(names scope);'entries';entries
 end.
 out,<emit 'cost max';(>./0,sizes);'total';+/sizes
)
enumerate =: 3 : 0
 'q ev es relevant maximize' =. y
 free =. relevant-.ev
 vals =. (*/q{K)$0.0
 best =. _1
 bestrow =. NV$0
 for_a. assignments free do.
  row =. NV$0
  row =. es ev}row
  row =. a free}row
  value =. 1.0
  for_v. relevant do. value =. value*v probability row end.
  if. maximize do.
   if. value>best do. best =. value
   bestrow =. row end.
  else.
   i =. q row_number row
   vals =. ((i{vals)+value)i}vals
  end.
 end.
 if. maximize do. best;bestrow else. (vals%sum vals);sum vals end.
)
main =: 3 : 0
 read_network ''
 1!:5 :: 0: <'output'
 structure ''
 learn ''
 allfs =. cpt_factor&.>i.NV
 minplan =. plan allfs;(i.NV);0
 givenplan =. plan allfs;(i.NV);1
 moral =. (NV,NV)$0
 for_v. i.NV do.
  scope =. v,v{::Parents
  for_a. scope do. moral =. 1(<a;scope-.a)}moral end.
 end.
 width1 =. _1+>./#@:(2&{::)&>minplan
 width2 =. _1+>./#@:(2&{::)&>givenplan
 struct =. (<emit 'variables';NV;'edges';+/#&>Parents),(<emit 'topological_order';names Topological),(<emit 'roots';names I.0=#&>Parents),(<emit 'leaves';names I.0=#&>Children),<emit 'moral_edges';((+/,moral)%2);'width minfill';width1;'given';width2
 cptlines =. 0$a:
 for_v. i.NV do.
  ps =. v{::Parents
  struct =. struct,<emit 'variable';(v{::VNames);'states';(v{K);'parents';(#ps);'children';(#v{::Children);'depth';(v{Depth);'ancestors';(_1+#ancestors ,v);'descendants';(_1+#closure_children ,v);'blanket';#blanket v
  cptlines =. cptlines,(<emit 'variable';(v{::VNames);'source';v{::Source),(<emit 'states';' 'join v{::States),<emit 'parents';names ps
  a =. assignments ps
  for_r. i.#a do.
   row =. NV$0
   row =. (r{a)ps}row
   cptlines =. cptlines,<emit 'row';(ps assignment_text row);'counts';(emit <"0 r{v{::Counts);'probs';' 'join fixed&.>r{v{::CPTs
  end.
  result =. infer (,v);(i.0);(i.0);(Used-:'GIVEN');0
  marginal =. v{::marginals (3{::result);4{::result
  data =. i.0
  for_s. i.v{K do. data =. data,(+/s=v{"1 Data)%NS end.
  cptlines =. cptlines,<emit 'loglik';(fixed v{LLs);'parameters';(v{Dimensions);'bic';fixed v{BICs
  cptlines =. cptlines,<emit 'marginal model';(' 'join fixed&.>marginal);'data';' 'join fixed&.>data
  if. 'LEARNED'-:v{::Source do.
   diff =. '-'
   if. #v{::Given do. diff =. fixed >./,|(v{::Learned)-v{::Given end.
   cptlines =. cptlines,<emit 'given_difference';diff
  end.
  cptlines =. cptlines,<''
 end.
 ll =. sum LLs
 d =. +/Dimensions
 cptlines =. cptlines,<emit 'network samples';NS;'pseudocount';(fixed Alpha);'loglik';(fixed ll);'parameters';d;'bic';fixed ll-(d*^.NS)%2
 answers =. eliminationlines =. 0$a:
 samplelines =. <'query,samples,variable,state,estimate,exact,abs_error'
 for_qi. i.#Queries do.
  text =. qi{::Queries
  fields =. words text
  kind =. 0{::fields
  header =. emit 'query';(qi+1);text
  body =. 0$a:
  if. (<kind)e.'QUERY';'MPE';'SAMPLE' do.
   rest =. }.fields
   counts =. i.0
   ci =. rest i.<'COUNTS'
   if. ci<#rest do. counts =. num&>(ci+1)}.rest
   rest =. ci{.rest end.
   if. kind-:'MPE' do. q =. i.0
   'ev es' =. evidence rest
   else.
    bar =. rest i.<'|'
    q =. VNames i.bar{.rest
    ef =. 0$a:
    if. bar<#rest do. ef =. (bar+1)}.rest end.
    'ev es' =. evidence ef
   end.
   maximize =. kind-:'MPE'
   usedgiven =. Used-:'GIVEN'
   r0 =. infer q;ev;es;0;maximize
   r1 =. infer q;ev;es;1;maximize
   r =. r0
   if. usedgiven do. r =. r1 end.
   'relevant elim pl scope values z row' =. r
   marginal =. marginals scope;values
   if. kind-:'QUERY' do.
    body =. body,<emit 'log_evidence';fixed ^.z
    if. #ev do.
     conflict =. -^.z
     for_i. i.#ev do. rz =. infer (i.0);(,i{ev);(,i{es);usedgiven;0
     conflict =. conflict+^.5{::rz end.
     body =. body,<emit 'conflict';fixed conflict
    end.
    if. 1<#q do.
     a =. assignments scope
     for_i. i.#a do. ar =. NV$0
     ar =. (i{a)scope}ar
     body =. body,<emit 'joint';(scope assignment_text ar);fixed i{values end.
    end.
    body =. body,'marginal'distribution_lines q;marginal
    for_i. i.#ev do.
     keep =. (i.#ev)-.i
     rd =. infer q;(keep{ev);(keep{es);usedgiven;0
     md =. marginals (3{::rd);4{::rd
     shift =. 0.0
     for_v. q do. shift =. shift>.>./|(v{::marginal)-v{::md end.
     erow =. NV$0
     erow =. (i{es)(i{ev)}erow
     body =. body,<emit 'drop';((,i{ev)assignment_text erow);'shift';fixed shift
    end.
   elseif. maximize do.
    rz =. infer (i.0);ev;es;usedgiven;0
    ze =. 5{::rz
    body =. (<emit 'assignment';(i.NV)assignment_text row),(<emit 'log_joint';fixed ^.z),(<emit 'log_evidence';fixed ^.ze),<emit 'posterior';fixed z%ze
    for_v. (i.NV)-.ev do.
     rm =. infer (,v);ev;es;usedgiven;1
     vv =. 4{::rm
     candidates =. (i.v{K)-.v{row
     second =. ({.\:candidates{vv){candidates
     body =. body,<emit 'margin';(v{::VNames);(second{::v{::States);fixed (^.z)-^.second{vv
    end.
   else.
    body =. 'exact'distribution_lines q;marginal
    weights =. NV$<i.0
    for_v. q do. weights =. (<(v{K)$0.0)v}weights end.
    total =. squared =. 0.0
    for_i. 1+i.{:counts do.
     'draw w' =. weighted_sample ev;es
     total =. total+w
     squared =. squared+w*w
     for_v. q do. a =. v{::weights
     s =. v{draw
     a =. ((s{a)+w)s}a
     weights =. (<a)v}weights end.
     if. i e.counts do.
      maximum =. 0.0
      for_v. q do.
       estimate =. (v{::weights)%total
       exact =. v{::marginal
       errs =. |estimate-exact
       maximum =. maximum>.>./errs
       for_s. i.v{K do. samplelines =. samplelines,<','join (str qi+1);(str i);(v{::VNames);(s{::v{::States);(fixed s{estimate);(fixed s{exact);fixed s{errs end.
      end.
      body =. body,<emit 'after';i;'weight';(fixed total);'ess';(fixed (total*total)%squared);'max_error';fixed maximum
     end.
    end.
   end.
   if. -.kind-:'SAMPLE' do.
    eb =. (<header),(<emit 'relevant';names relevant),(<emit 'pruned';names (i.NV)-.relevant),<emit 'eliminate';names elim
    eb =. eb,('minfill'plan_report 2{::r0),'given'plan_report 2{::r1
    agree =. 1e_9>:|(^.5{::r0)-^.5{::r1
    if. maximize do. agree =. agree*.(6{::r0)-:6{::r1
    else. agree =. agree*.*./1e_9>:|(4{::r0)-4{::r1 end.
    count =. */(relevant-.ev){K
    verdict =. 'skipped'
    if. count<:EnumLimit do.
     er =. enumerate scope;ev;es;relevant;maximize
     if. maximize do. ok =. ((1{::er)-:row)*.1e_9>:|(^.0{::er)-^.z
     else. ok =. (*./1e_9>:|(0{::er)-values)*.1e_9>:|(^.1{::er)-^.z end.
     verdict =. ok{::'disagree';'agree'
    end.
    eb =. eb,(<emit 'used';usedgiven{::'minfill';'given'),(<emit 'orders_agree';agree{::'no';'yes'),<emit 'enumeration';count;verdict
    if. #eliminationlines do. eliminationlines =. eliminationlines,<'' end.
    eliminationlines =. eliminationlines,eb
   end.
  elseif. kind-:'PREDICT' do.
   v =. VNames i.1{fields
   confusion =. ((v{K),v{K)$0
   loss =. 0.0
   for_row. Data do.
    actual =. v{row
    probs =. i.0
    for_s. i.v{K do.
     draw =. s v}row
     pp =. v probability draw
     for_c. v{::Children do. pp =. pp*c probability draw end.
     probs =. probs,pp
    end.
    probs =. probs%sum probs
    pred =. probs i.>./probs
    confusion =. (1+(<actual,pred){confusion)(<actual,pred)}confusion
    loss =. loss-^.actual{probs
   end.
   correct =. +/(<"1(i.v{K),.i.v{K){confusion
   body =. (<emit 'blanket';names blanket v),(<emit 'accuracy';((str correct),'/',str NS);fixed correct%NS),(<emit 'log_loss';fixed loss%NS),<emit 'predicted';' 'join v{::States
   for_s. i.v{K do. body =. body,<emit 'actual';(s{::v{::States);emit <"0 s{confusion end.
  elseif. kind-:'BLANKET' do.
   v =. VNames i.1{fields
   mb =. blanket v
   ps =. v{::Parents
   cs =. v{::Children
   spouses =. mb-.ps,cs
   rest =. (i.NV)-.v,mb
   reach =. bayes_ball (,v);mb
   body =. (<emit 'parents';names ps),(<emit 'children';names cs),(<emit 'spouses';names spouses),(<emit 'blanket';names mb),(<emit 'rest';names rest),<emit 'rest_separated';(-.+./rest e.reach){::'no';'yes'
  elseif. kind-:'DSEP' do.
   f =. }.fields
   bars =. I.f=< '|'
   xs =. VNames i.(0{bars){.f
   ystart =. 1+0{bars
   yend =. #f
   if. 1<#bars do. yend =. 1{bars end.
   ys =. VNames i.(yend-ystart){.ystart}.f
   zs =. i.0
   if. 1<#bars do. zs =. VNames i.(1+1{bars)}.f end.
   reach =. bayes_ball xs;zs
   cmi =. 0.0
   scope =. /:~xs,ys,zs
   for_a. assignments scope do.
    row =. NV$0
    row =. a scope}row
    nw =. nx =. ny =. nz =. 0
    for_d. Data do.
     nw =. nw+*./(scope{row)=scope{d
     nx =. nx+*./((xs,zs){row)=(xs,zs){d
     ny =. ny+*./((ys,zs){row)=(ys,zs){d
     nz =. nz+*./(zs{row)=zs{d
    end.
    if. nw do. cmi =. cmi+(nw%NS)*^. (nw*nz)%(nx*ny) end.
   end.
   df =. (((*/xs{K)-1)*((*/ys{K)-1))**/zs{K
   body =. (<emit 'result';(+./ys e.reach){::'separated';'connected'),(<emit 'reachable';names reach),<emit 'data cmi';(fixed cmi);'g2';(fixed 2*NS*cmi);'df';df
  elseif. kind-:'EDGE' do.
   op =. 1{::fields
   'x y' =. VNames i.2 3{fields
   ps =. y{::Parents
   exists =. x e.ps
   cycle =. i.0
   verdict =. 'ok'
   if. op-:'ADD' do.
    if. exists do. verdict =. 'exists' else. cycle =. path y,x,_1,_1
    cycle =. x,cycle end.
    if. 1=#cycle do. cycle =. i.0 end.
   else.
    if. -.exists do. verdict =. 'missing'
    elseif. op-:'REVERSE' do. cycle =. path x,y,x,y
    cycle =. y,cycle
    if. 1=#cycle do. cycle =. i.0 end. end.
   end.
   if. #cycle do. body =. <emit 'result cycle';' -> 'join cycle{VNames
   elseif. -.verdict-:'ok' do. body =. <emit 'result';verdict
   else.
    newps =. /:~ps-.x
    if. op-:'ADD' do. newps =. /:~ps,x end.
    before =. 4{::y family /:~ps
    after =. 4{::y family newps
    change =. after-before
    body =. (<'result ok'),<emit 'family';(y{::VNames);'before';(fixed before);'after';fixed after
    if. op-:'REVERSE' do.
     px =. /:~x{::Parents
     bx =. 4{::x family px
     ax =. 4{::x family /:~px,y
     change =. change+ax-bx
     body =. body,<emit 'family';(x{::VNames);'before';(fixed bx);'after';fixed ax
    end.
    body =. body,<emit 'delta';(fixed change);(change>0){::'worsens';'improves'
   end.
  end.
  if. (<kind)e.'DSEP';'BLANKET';'EDGE' do. struct =. struct,(<''),(<header),body
  else. if. #answers do. answers =. answers,<'' end.
  answers =. answers,(<header),body end.
 end.
 'cpts.txt'write cptlines
 'structure.txt'write struct
 'answers.txt'write answers
 'elimination.txt'write eliminationlines
 'sampling.csv'write samplelines
 i.0 0
)
main ''
