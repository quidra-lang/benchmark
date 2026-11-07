words =: 3 : '<;._1 '' '',y'
lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
num =: 3 : '0".''_''(I.y=''-'')}y'
csv =: 3 : 0
 out =. 0$a:
 for_l. }.lines y do. out =. out,< <;._1 ',',>l end.
 out
)
read_model =: 3 : 0
 a =. csv 'nodes.csv'
 NodeIds =: num&>0{&>a
 Coordinates =: 0 2$0
 for_row. a do. Coordinates =: Coordinates,num&>}.>row end.
 NN =: #NodeIds
 SectionNames =: 0$a:
 Sections =: 0 2$0.0
 for_l. csv 'sections.csv' do. f =. >l
 SectionNames =: SectionNames,{.f
 Sections =: Sections,num&>}.f end.
 MaterialNames =: 0$a:
 Materials =: 0 4$0.0
 for_l. csv 'materials.csv' do. f =. >l
 MaterialNames =: MaterialNames,{.f
 Materials =: Materials,num&>}.f end.
 MemberIds =: Mi =: Mj =: InitialSections =: Material =: Group =: i.0
 GroupNames =: 0$a:
 for_l. csv 'members.csv' do.
  'id ni nj sec mat group' =. >l
  MemberIds =: MemberIds,num id
  Mi =: Mi,NodeIds i.num ni
  Mj =: Mj,NodeIds i.num nj
  InitialSections =: InitialSections,SectionNames i.<sec
  Material =: Material,MaterialNames i.<mat
  if. -.(<group)e.GroupNames do. GroupNames =: GroupNames,<group end.
  Group =: Group,GroupNames i.<group
 end.
 NM =: #Mi
 Supports =: 0 5$0.0
 for_l. csv 'supports.csv' do. f =. >l
 Supports =: Supports,(NodeIds i.num 0{::f),num&>}.f end.
 CaseNames =: LoadCases =: ComboNames =: Combinations =: 0$a:
 current =. 0$a:
 for_l. lines 'loads.txt' do.
  f =. words >l
  select. 0{::f
  case. 'LOADCASE' do. CaseNames =: CaseNames,1{f
  current =. 0$a:
  case. 'END' do. LoadCases =: LoadCases,<current
  case. 'COMBINATION' do.
   ComboNames =: ComboNames,1{f
   pairs =. 0 2$0.0
   for_i. 2+2*i.<.((#f)-2)%2 do. pairs =. pairs,(CaseNames i.i{f),num (i+1){::f end.
   Combinations =: Combinations,<pairs
  case. do. current =. current,<f
  end.
 end.
 NC =: #CaseNames
 ResultNames =: CaseNames,ComboNames
 Keys =: Values =: Drawings =: 0$a:
 Influences =: i.0
 for_l. lines 'params.txt' do.
  f =. words >l
  select. 0{::f
  case. 'influence' do. Influences =: Influences,MemberIds i.num 1{::f
  case. 'drawing' do. Drawings =: Drawings,<}.f
  case. do. Keys =: Keys,{.f
  Values =: Values,<}.f
  end.
 end.
 Deck =: NodeIds i.num&>pv 'deck'
 DeckX =: 0{"1 Deck{Coordinates
 i.0 0
)
pv =: 3 : '(Keys i.<y){::Values'
