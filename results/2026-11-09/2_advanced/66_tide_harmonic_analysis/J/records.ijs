words =: 3 : '<;._1 '' '',y'
lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
num =: 3 : '0".''_''(I.y=''-'')}y'
leap =: 3 : '(0=4|y)*.((0~:100|y)+.0=400|y)'
days =: 3 : 0
 'yr mo da' =. y
 yy =. yr-1
 md =. 31,(28+leap yr),31 30 31 30 31 31 30 31 30 31
 base =. 365*yy
 base =. base+<.yy%4
 base =. base-<.yy%100
 base =. base+<.yy%400
 (base++/(mo-1){.md)+da-1
)
parse_date =: 3 : 0
 yr =. num 4{.y
 mo =. num 2{.5}.y
 da =. num 2{.8}.y
 hr =. num 2{.11}.y
 mi =. num 2{.14}.y
 (1440*days yr,mo,da)+(60*hr)+mi
)
datetime =: 3 : 0
 m =. Epoch+y
 day =. <.m%1440
 yr =. 1+<.day%366
 while. (days (yr+1),1 1)<:day do. yr =. yr+1 end.
 while. (days yr,1 1)>day do. yr =. yr-1 end.
 rem =. day-days yr,1 1
 md =. 31,(28+leap yr),31 30 31 30 31 31 30 31 30 31
 mo =. 0
 while. rem>:mo{md do. rem =. rem-mo{md
 mo =. mo+1 end.
 (str yr),'-',(_2{.'00',str mo+1),'-',(_2{.'00',str rem+1),' ',(_2{.'00',str <.(1440|m)%60),':',_2{.'00',str 60|m
)
date =: 3 : '10{.datetime y'
time =: 3 : 'datetime 60*y'
read_records =: 3 : 0
 Codes =: StationNames =: Keys =: Values =: 0$a:
 for_l. lines 'params.txt' do.
  f =. words >l
  k =. 0{::f
  if. k-:'epoch' do. Epoch =: parse_date ' 'join }.f
  elseif. k-:'station' do. Codes =: Codes,1{f
  StationNames =: StationNames,<' 'join 2}.f
  else. Keys =: Keys,<k
  Values =: Values,<}.f end.
 end.
 c =. }.lines 'constituents.txt'
 CNames =: 0$a:
 Speeds =: i.0
 for_l. c do. f =. words >l
 CNames =: CNames,{.f
 Speeds =: Speeds,num 1{::f end.
 Times =: (#Codes)$<i.0
 Heights =: (#Codes)$<i.0
 Numeric =: (#Codes)$<i.0
 for_l. }.lines 'observations.csv' do.
  'code stamp value' =. <;._1 ',',>l
  s =. Codes i.<code
  Times =: (<(s{::Times),<.((parse_date stamp)-Epoch)%60)s}Times
  good =. -.value-:'NA'
  v =. 0.0
  if. good do. v =. num value end.
  Heights =: (<(s{::Heights),v)s}Heights
  Numeric =: (<(s{::Numeric),good)s}Numeric
 end.
 'ps pd plen' =. pv 'predict'
 Ts =: <.((parse_date ps,' ',pd)-Epoch)%60
 P =: num plen
 PlotCode =: 0{::pv 'plot'
 PlotValues =: num&>}.pv 'plot'
 i.0 0
)
pv =: 3 : '(Keys i.<y){::Values'
pn =: 3 : 'num 0{::pv y'
