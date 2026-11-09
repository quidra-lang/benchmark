ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'model_io.ijs'
load SourceDirectory,'solver.ijs'
load SourceDirectory,'assembly.ijs'
load SourceDirectory,'postprocess.ijs'
load SourceDirectory,'design.ijs'
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
 s =. ''
 for_i. i.#y do. if. i do. s =. s,x end.
 s =. s,str i{::y end.
 s
)
emit =: 3 : ''' ''join y'
fmt =: 4 : 0
 n =. <.0.5+(10^x)*|y
 t =. (str <.n%10^x),'.',(-x){.(x#'0'),str (10^x)|n
 if. (y<0)*.n>0 do. '-',t else. t end.
)
fixed =: 3 : '4 fmt y'
rounded =: 3 : '(*y)*<.0.5+10000*|y'
argmax =: 3 : '({.\:rounded y)'
argmin =: 3 : '({./:rounded y)'
sum =: 3 : 0
 s =. 0.0
 for_v. y do. s =. s+v end.
 s
)
write =: 4 : 0
 (;(,&LF)&.>y)1!:2 <'output/',x
 i.0 0
)
node_displacements =: 3 : 'y{~Dofs'
utilizations =: 3 : 0
 answer =. i.0
 for_m. i.NM do. answer =. answer,utilization m;(m{y);(m{Areas);m{Moments end.
 answer
)
numbering_stats =: 3 : 0
 bandwidth =. >./|(Mi{y)-Mj{y
 profile =. 0
 for_v. i.NN do. profile =. profile+(v{y)-<./(v,I.v{Adjacent){y end.
 bandwidth,profile
)
ordinate =: 4 : 0
 if. (y<{.DeckX)+.y>{:DeckX do. 0.0 return. end.
 if. y={:DeckX do. {:x return. end.
 k =. _1++/DeckX<:y
 (k{x)+(((k+1){x)-k{x)*(y-k{DeckX)%((k+1){DeckX)-k{DeckX
)
vehicle_effect =: 3 : 0
 out =. i.0
 for_p. VehiclePositions do.
  total =. 0.0
  for_a. i.#AxleOffsets do. total =. total+(a{AxleLoads)*(y ordinate p-a{AxleOffsets) end.
  out =. out,total
 end.
 out
)
point =: 3 : '(2+<.0.5+(({.y)-X0)%CW),2+<.0.5+(Y1-{:y)%CH'
put =: 4 : 0
 'c r' =. y
 if. (c>:0)*.(c<DW)*.(r>:0)*.r<DH do. Canvas =: x(<r,c)}Canvas end.
 i.0 0
)
line =: 4 : 0
 'c r c1 r1' =. y
 dc =. |c1-c
 dr =. -|r1-r
 sc =. (c<c1){_1 1
 sr =. (r<r1){_1 1
 err =. dc+dr
 while. 1 do.
  x put c,r
  if. (c=c1)*.r=r1 do. break. end.
  e2 =. 2*err
  if. e2>:dr do. err =. err+dr
  c =. c+sc end.
  if. e2<:dc do. err =. err+dc
  r =. r+sr end.
 end.
 i.0 0
)
make_drawing =: 3 : 0
 'd magnify wc hc map' =. y
 CW =: wc
 CH =: hc
 X0 =: <./0{"1 Coordinates
 X1 =: >./0{"1 Coordinates
 Y0 =: <./1{"1 Coordinates
 Y1 =: >./1{"1 Coordinates
 DW =: 5+<.0.5+(X1-X0)%wc
 DH =: 5+<.0.5+(Y1-Y0)%hc
 Canvas =: (DH,DW)$' '
 positions =. point"1 Coordinates
 if. map do.
  for_m. i.NM do.
   u =. m{Governing
   ch =. '#'
   if. u<1 do. ch =. (<.10*u){'0123456789' end.
   ch line ((m{Mi){positions),((m{Mj){positions)
  end.
  for_p. positions do. 'o'put p end.
 else.
  for_m. i.NM do. '.'line ((m{Mi){positions),((m{Mj){positions) end.
  for_p. positions do. '+'put p end.
  positions =. point"1 Coordinates+magnify*node_displacements d
  for_m. i.NM do. '*'line ((m{Mi){positions),((m{Mj){positions) end.
  for_p. positions do. 'o'put p end.
 end.
 border =. '+',(DW#'-'),'+'
 out =. <border
 for_row. Canvas do. out =. out,<'|',row,'|' end.
 (<DW;DH);out,<border
)
main =: 3 : 0
 read_model ''
 properties ''
 1!:5 :: 0: <'output'
 CurrentSections =: InitialSections
 designlines =. 0$a:
 converged =. 0
 for_round. 1+i.10 do.
  Results =: analyse _1
  Lim =: limits Results
  us =. (0,NM)$0.0
  for_r. NC}.Results do. us =. us,utilizations 1{::>r end.
  flat =. ,|:us
  at =. argmax flat
  m =. <.at%(#ComboNames)
  combination =. (#ComboNames)|at
  new =. choose_sections Results;Lim
  old =. i.0
  for_g. i.#GroupNames do. old =. old,({.I.Group=g){CurrentSections end.
  changed =. I.old~:new
  weight =. (sum Weights)%1000
  designlines =. designlines,<emit 'round';round;'weight';(fixed weight);'max_utilization';(fixed at{flat);'at';(m{MemberIds);(combination{::ComboNames);'changes';#changed
  for_g. changed do.
   ids =. I.Group=g
   values =. ,ids{"1 us
   designlines =. designlines,<emit 'change';(g{::GroupNames);((g{old){::SectionNames);((g{new){::SectionNames);'utilization';fixed (argmax values){values
  end.
  if. 0=#changed do. converged =. 1
  break. end.
  if. round<10 do. CurrentSections =: Group{new end.
 end.
 designlines =. designlines,<emit 'result';(converged{::'not_converged';'converged');'rounds';round
 Governing =: NM$0.0
 GovCombo =: NM$0
 for_m. i.NM do. v =. m{"1 us
 i =. argmax v
 Governing =: (i{v)m}Governing
 GovCombo =: i m}GovCombo end.
 for_g. i.#GroupNames do.
  ids =. I.Group=g
  m =. (argmax ids{Governing){ids
  designlines =. designlines,<emit 'group';(g{::GroupNames);'section';((m{CurrentSections){::SectionNames);'members';(#ids);'utilization';(fixed m{Governing);'at';m{MemberIds
 end.
 for_m. i.NM do.
  sl =. slenderness m;(m{Areas);m{Moments
  ok =. ((m{Governing)<:1)*.sl<:m{Lim
  designlines =. designlines,<emit 'member';(m{MemberIds);'group';((m{Group){::GroupNames);'section';((m{CurrentSections){::SectionNames);'utilization';(fixed m{Governing);'governing';((m{GovCombo){::ComboNames);'slenderness';(fixed sl);'limit';(fixed m{Lim);ok{::'over';'ok'
 end.
 ranking =. \:rounded Governing
 for_i. i.5<.NM do. m =. i{ranking
 designlines =. designlines,<emit 'rank';(i+1);'member';(m{MemberIds);'utilization';fixed m{Governing end.
 for_m. i.NM do.
  vals =. i.0
  for_r. NC}.Results do. vals =. vals,(m{1{::>r)%1000 end.
  hi =. argmax vals
  lo =. argmin vals
  designlines =. designlines,<emit 'envelope';(m{MemberIds);'max';(fixed hi{vals);(hi{::ComboNames);'min';(fixed lo{vals);lo{::ComboNames
 end.
 for_s. i.#Sections do.
  ids =. I.CurrentSections=s
  if. #ids do. designlines =. designlines,<emit 'section';(s{::SectionNames);'members';(#ids);'length';fixed sum ids{Lengths end.
 end.
 designlines =. designlines,<emit 'weight';fixed weight
 before =. numbering_stats i.NN
 after =. numbering_stats NewNumber
 analysis =. (<emit 'model nodes';NN;'members';NM;'supports';(#Supports);'free_dofs';(#Free);'restrained_dofs';(#Restrained);'indeterminacy';NM+(#Restrained)-2*NN),(<emit 'renumbering';emit <"0 Renumbering{NodeIds),(<emit 'bandwidth before';(0{before);'after';0{after),<emit 'profile before';(1{before);'after';1{after
 for_m. i.NM do. analysis =. analysis,<emit 'member';(m{MemberIds);'nodes';((m{Mi){NodeIds);((m{Mj){NodeIds);'length';(fixed m{Lengths);'cos';(6 fmt m{Cosines);'sin';6 fmt m{Sines end.
 disp =. <'case,node,dx,dy'
 forcecsv =. <'case,member,force,stress,utilization'
 reactionscsv =. <'case,node,rx,ry'
 for_k. i.#Results do.
  name =. k{::ResultNames
  'd ns r fe' =. k{::Results
  nd =. node_displacements d
  mags =. %:+/"1 *:nd
  at =. argmax mags
  energy =. (sum (((ns*ns)*Lengths)%(2*E*Areas)))%1000
  sr =. (sum (0{"1 Dofs){r),(sum (1{"1 Dofs){r)
  sf =. (sum (0{"1 Dofs){fe),(sum (1{"1 Dofs){fe)
  analysis =. analysis,<emit ((k<NC){::'combination';'case');name;'equilibrium';((equilibrium k{::Results){::'failed';'ok');'max_displacement';(fixed at{mags);'at';(at{NodeIds);'energy';(fixed energy);'reactions';(' 'join fixed&.>sr%1000);'loads';' 'join fixed&.>sf%1000
  for_n. i.NN do. disp =. disp,<','join name;(str n{NodeIds);(fixed (<n,0){nd);fixed (<n,1){nd end.
  u =. utilizations ns
  for_m. i.NM do. forcecsv =. forcecsv,<','join name;(str m{MemberIds);(fixed (m{ns)%1000);(fixed (m{ns)%m{Areas);fixed m{u end.
  for_sup. Supports do. n =. 0{sup
  ds =. n{Dofs
  reactionscsv =. reactionscsv,<','join name;(str n{NodeIds);(fixed (0{ds){r%1000);fixed (1{ds){r%1000 end.
 end.
 for_sup. Supports do.
  n =. 0{sup
  for_dir. i.2 do.
   if. -.(dir+1){sup do. continue. end.
   df =. (<n,dir){Dofs
   vals =. i.0
   for_r. NC}.Results do. vals =. vals,(df{2{::>r)%1000 end.
   hi =. argmax vals
   lo =. argmin vals
   text =. emit 'reaction_envelope';(n{NodeIds);(,dir{'xy');'max';(fixed hi{vals);(hi{::ComboNames);'min';(fixed lo{vals);lo{::ComboNames
   if. dir do. text =. text,emit ' uplift';(+./vals<0){::'no';'yes' end.
   analysis =. analysis,<text
  end.
 end.
 for_n. i.NN do.
  vals =. i.0
  for_r. NC}.Results do. uv =. (n{Dofs){0{::>r
  vals =. vals,%:sum *:uv end.
  hi =. argmax vals
  analysis =. analysis,<emit 'displacement_envelope';(n{NodeIds);'max';(fixed hi{vals);hi{::ComboNames
 end.
 'defname ratio' =. pv 'deflection'
 dr =. (ResultNames i.<defname){::Results
 ddy =. (1{"1 Dofs){0{::dr
 supported =. Deck#~(1{"1 Deck{Dofs)e.Restrained
 for_i. i.(#supported)-1 do.
  a =. i{supported
  b =. (i+1){supported
  xa =. (<a,0){Coordinates
  xb =. (<b,0){Coordinates
  ids =. Deck#~(DeckX>:xa)*.DeckX<:xb
  deltas =. i.0
  for_n. ids do.
   xx =. (<n,0){Coordinates
   deltas =. deltas,|(n{ddy)-((a{ddy)+((b{ddy)-a{ddy)*(xx-xa)%(xb-xa))
  end.
  at =. argmax deltas
  n =. at{ids
  maximum =. at{deltas
  limit =. (xb-xa)%num ratio
  analysis =. analysis,<emit 'deflection';defname;'span';(a{NodeIds);(b{NodeIds);'max';(fixed maximum);'at';(n{NodeIds);'limit';(fixed limit);(maximum<:limit){::'exceeded';'ok'
  unit =. 0{::unit_result n
  vw =. sum ((((1{::dr)*(unit%1000))*Lengths)%(E*Areas))
  st =. -n{ddy
  ok =. (|vw-st)<:1e_6*1>.|st
  analysis =. analysis,<emit 'virtual_work';defname;'node';(n{NodeIds);'stiffness';(fixed st);'virtual';(fixed vw);ok{::'failed';'ok'
 end.
 saved =. Results
 removalname =. 0{::pv 'removal'
 for_removed. i.NM do.
  altered =. analyse removed
  if. Unstable>:0 do.
   df =. Unstable{Free
   node =. (<.df%2){Renumbering
   analysis =. analysis,<emit 'removal';(removed{MemberIds);'unstable at';(node{NodeIds);, (2|df){'xy'
  else.
   r =. (ResultNames i.<removalname){::altered
   u =. utilizations 1{::r
   u =. _1 removed}u
   m =. argmax u
   magnitudes =. %:+/"1 *:node_displacements 0{::r
   n =. argmax magnitudes
   analysis =. analysis,<emit 'removal';(removed{MemberIds);'stable max_utilization';(fixed m{u);'at';(m{MemberIds);'max_displacement';(fixed n{magnitudes);'at';n{NodeIds
  end.
 end.
 Results =: saved
 assemble _1
 nf =. (0,NM)$0.0
 nr =. (0,ND)$0.0
 for_n. Deck do. 'nforce reaction' =. unit_result n
 nf =. nf,nforce%1000
 nr =. nr,reaction%1000 end.
 influencelines =. 0$a:
 for_m. Influences do.
  values =. m{"1 nf
  influencelines =. influencelines,<emit 'influence';m{MemberIds
  for_i. i.#Deck do. influencelines =. influencelines,<emit 'node';((i{Deck){NodeIds);fixed i{values end.
  hi =. argmax values
  lo =. argmin values
  influencelines =. influencelines,<emit 'max';(fixed hi{values);'at';((hi{Deck){NodeIds);'min';(fixed lo{values);'at';((lo{Deck){NodeIds);'positive';(fixed sum values#~values>0);'negative';fixed sum values#~values<0
  crossings =. i.0
  for_i. i.(#Deck)-1 do.
   aa =. i{values
   bb =. (i+1){values
   if. (aa*bb)<0 do. crossings =. crossings,(i{DeckX)+(((i+1){DeckX)-i{DeckX)*aa%(aa-bb) end.
  end.
  text =. emit 'crossings';#crossings
  if. #crossings do. text =. text,' ',' 'join 1&fmt&.>crossings end.
  influencelines =. influencelines,<text
 end.
 v =. num&>pv 'vehicle'
 step =. {.v
 axles =. _2[\}.v
 AxleOffsets =: 0{"1 axles
 AxleLoads =: 1{"1 axles
 VehiclePositions =: ({.DeckX)+step*i.1+<.(({:DeckX)+({:AxleOffsets)-{.DeckX)%step
 influencelines =. influencelines,<emit 'vehicle axles';(#axles);'positions';#VehiclePositions
 effects =. 0$a:
 for_m. i.NM do.
  values =. vehicle_effect m{"1 nf
  effects =. effects,<values
  hi =. argmax values
  lo =. argmin values
  influencelines =. influencelines,<emit 'vehicle_member';(m{MemberIds);'max';(fixed hi{values);'at';(hi{VehiclePositions);'min';(fixed lo{values);'at';lo{VehiclePositions
 end.
 for_sup. Supports do.
  n =. 0{sup
  for_dir. i.2 do.
   if. -.(dir+1){sup do. continue. end.
   values =. vehicle_effect ((<n,dir){Dofs){"1 nr
   hi =. argmax values
   lo =. argmin values
   influencelines =. influencelines,<emit 'vehicle_reaction';(n{NodeIds);(,dir{'xy');'max';(fixed hi{values);'at';(hi{VehiclePositions);'min';(fixed lo{values);'at';lo{VehiclePositions
  end.
 end.
 'ratingname gd gl' =. pv 'rating'
 gd =. num gd
 gl =. num gl
 dead =. (1{::(ResultNames i.<ratingname){::Results)%1000
 ratingvalues =. ratingmembers =. ratingkinds =. i.0
 for_m. i.NM do.
  values =. m{::effects
  tension =. (argmax values){values
  compression =. (argmin values){values
  pt =. (m{Areas)*(m{Fy)%1000
  pc =. ((m{Areas)*(m{Fy))<.m pcr m{Moments
  pc =. pc%1000
  rt =. rc =. 'none'
  if. (rounded tension)>0 do.
   v =. (pt-gd*m{dead)%(gl*tension)
   rt =. fixed v
   ratingvalues =. ratingvalues,v
   ratingmembers =. ratingmembers,m
   ratingkinds =. ratingkinds,0
  end.
  if. (rounded compression)<0 do.
   v =. (pc+gd*m{dead)%(gl*-compression)
   rc =. fixed v
   ratingvalues =. ratingvalues,v
   ratingmembers =. ratingmembers,m
   ratingkinds =. ratingkinds,1
  end.
  influencelines =. influencelines,<emit 'rating';(m{MemberIds);'tension';rt;'compression';rc
 end.
 i =. argmin ratingvalues
 influencelines =. influencelines,<emit 'rating_min';(fixed i{ratingvalues);'at';((i{ratingmembers){MemberIds);(i{ratingkinds){::'tension';'compression'
 'vibname nm iterations' =. pv 'vibration'
 massforce =. 3{::(ResultNames i.<vibname){::Results
 masses =. -((1{"1 Dofs){massforce)%9.81
 mf =. ((<.Free%2){Renumbering){masses
 vibrationlines =. <emit 'vibration';vibname;'mass';(fixed sum masses);'iterations';num iterations
 modes =. 0$a:
 for_mode. 1+i.num nm do.
  x =. (#Free)$1.0
  for_it. i.num iterations do.
   for_phi. modes do.
    phi =. >phi
    beta =. sum (phi*mf)*x
    x =. x-beta*phi
   end.
   yy =. Gchol solve mf*x
   nu =. %:sum (mf*yy)*yy
   x =. yy%nu
  end.
  modes =. modes,<x
  lambda =. (sum x*(Kff matvec x))%sum (mf*x)*x
  frequency =. (%:1000*lambda)%(2*3.141592653589793)
  shape =. ND$0.0
  largest =. {.\:|x
  shape =. (x%largest{x)Free}shape
  vibrationlines =. vibrationlines,<emit 'mode';mode;'frequency';(fixed frequency);'period';fixed 1%frequency
  for_n. i.NN do. ds =. n{Dofs
  vibrationlines =. vibrationlines,<emit 'node';(n{NodeIds);(fixed (0{ds){shape);fixed (1{ds){shape end.
 end.
 drawinglines =. 0$a:
 for_draw. Drawings do.
  'name mu wc hc' =. >draw
  d =. 0{::(ResultNames i.<name){::Results
  'size picture' =. make_drawing d;(num mu);(num wc);(num hc);0
  'dw dh' =. >size
  drawinglines =. drawinglines,(<emit 'drawing';name;'magnification';(num mu);'columns';dw;'rows';dh),picture
 end.
 'wc hc' =. num&>pv 'utilization_map'
 'size picture' =. make_drawing (ND$0);0;wc;hc;1
 'dw dh' =. >size
 drawinglines =. drawinglines,(<emit 'utilization_map columns';dw;'rows';dh),picture
 'analysis.txt'write analysis
 'displacements.csv'write disp
 'member_forces.csv'write forcecsv
 'reactions.csv'write reactionscsv
 'design.txt'write designlines
 'influence.txt'write influencelines
 'drawing.txt'write drawinglines
 'vibration.txt'write vibrationlines
 i.0 0
)
main ''
