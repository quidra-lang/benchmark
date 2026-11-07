words =: 3 : '<;._1 '' '',y'
lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
num =: 3 : '0".''_''(I.y=''-'')}y'
read_plans =: 3 : 0
 TypeNames =: 0$a:
 Types =: 0 3$0
 for_l. lines 'aircraft.txt' do. f =. words >l
 TypeNames =: TypeNames,{.f
 Types =: Types,num&>}.f end.
 Plans =: 0$a:
 Callsigns =: 0$a:
 for_l. }.lines 'flights.csv' do.
  f =. <;._1 ',',>l
  'name typ departure level speed wp' =. f
  waypoints =. 0 3$0
  for_w. words wp do.
   vals =. num&><;._1 ':',>w
   if. 2=#vals do. vals =. vals,_1 end.
   waypoints =. waypoints,vals
  end.
  Callsigns =: Callsigns,<name
  Plans =: Plans,<name;(TypeNames i.<typ);(num departure);(num level);(num speed);waypoints;0;0;num speed
 end.
 order =. /:Callsigns
 Callsigns =: order{Callsigns
 Plans =: order{Plans
 NF =: #Plans
 SectorNames =: 0$a:
 Sectors =: 0 7$0
 for_l. lines 'sectors.txt' do. f =. words >l
 SectorNames =: SectorNames,{.f
 Sectors =: Sectors,num&>}.f end.
 Keys =: Values =: 0$a:
 for_l. lines 'params.txt' do. f =. words >l
 Keys =: Keys,{.f
 Values =: Values,<num&>}.f end.
 'Dh Dv' =: pv 'separation'
 'Ta Tb' =: pv 'sampling'
 SampleTimes =: Ta+60*i.<.(Tb-Ta)%60
 'Rx0 Ry0 Rx1 Ry1 Rw Rh' =: pv 'radar'
 i.0 0
)
pv =: 3 : '(Keys i.<y){::Values'
pn =: 3 : '{.pv y'
