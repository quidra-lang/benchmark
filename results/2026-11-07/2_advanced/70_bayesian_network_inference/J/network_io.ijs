words =: 3 : '<;._1 '' '',y'
lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
num =: 3 : '0".''_''(I.y=''-'')}y'
read_network =: 3 : 0
 VNames =: States =: Parents =: Given =: 0$a:
 input =. lines 'network.txt'
 i =. 0
 while. i<#input do.
  text =. i{::input
  i =. i+1
  if. 0=#text do. continue. end.
  if. '#'={.text do. continue. end.
  f =. words text
  select. 0{::f
  case. 'VARIABLE' do.
   VNames =: VNames,1{f
   States =: States,<2}.f
   Parents =: Parents,<i.0
   Given =: Given,<i.0
  case. 'PARENTS' do.
   v =. VNames i.1{f
   Parents =: (<VNames i.2}.f)v}Parents
  case. 'CPT' do.
   v =. VNames i.1{f
   n =. */#&>(v{::Parents){States
   a =. 0$a:
   for_j. i.n do. a =. a,<num (i+j){::input end.
   Given =: (<>a)v}Given
   i =. i+n
  end.
 end.
 K =: #&>States
 NV =: #VNames
 Params =: ParamValues =: 0$a:
 Source =: 0$a:
 for_l. lines 'params.txt' do.
  f =. words >l
  if. 'SOURCE'-:0{::f do. Source =: Source,2{f
  else. Params =: Params,{.f
  ParamValues =: ParamValues,<}.f end.
 end.
 Alpha =: num 0{::pv 'PSEUDOCOUNT'
 Used =: 0{::pv 'ELIMINATION'
 Order =: VNames i.pv 'ORDER'
 EnumLimit =: num 0{::pv 'ENUMERATION_LIMIT'
 RNG =: num 0{::pv 'SEED'
 input =. lines 'samples.csv'
 header =. <;._1 ',',0{::input
 header =. VNames i.header
 Data =: (0,NV)$0
 for_l. }.input do.
  f =. <;._1 ',',>l
  row =. NV$0
  for_j. i.NV do. v =. j{header
  row =. ((v{::States)i.j{f)v}row end.
  Data =: Data,row
 end.
 NS =: #Data
 Queries =: lines 'queries.txt'
 i.0 0
)
pv =: 3 : '(Params i.<y){::ParamValues'
