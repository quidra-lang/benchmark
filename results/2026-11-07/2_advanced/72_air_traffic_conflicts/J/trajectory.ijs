Phases =: 'LVL';'CLB';'DES'
trajectory =: 3 : 0
 'name typ departure level originalspeed wps delay offset speed' =. y
 t =. departure+delay
 fl =. level+offset
 segments =. 0 14$0.0
 length =. 0.0
 for_k. 1+i.(#wps)-1 do.
  p =. (k-1){wps
  q =. k{wps
  diff =. 2{.q-p
  len =. (%:sum *:diff)%10
  duration =. (len*3600)%speed
  velxy =. (diff%10)%duration
  xy =. (2{.p)%10
  target =. fl
  if. (2{q)>:_0 do. target =. (2{q)+offset end.
  if. target=fl do.
   segments =. segments,(1+#segments),k,0,t,(t+duration),xy,(100*fl),velxy,0,((2{.q)%10),100*fl
  else.
   climb =. target>fl
   phase =. climb{2 1
   rate =. (<typ,climb{1 0){Types
   vz =. ((climb{_1 1)*rate)%60
   change =. (6000*|target-fl)%rate
   cx =. xy+velxy*change
   segments =. segments,(1+#segments),k,phase,t,(t+change),xy,(100*fl),velxy,vz,cx,100*target
   segments =. segments,(1+#segments),k,0,(t+change),(t+duration),cx,(100*target),velxy,0,((2{.q)%10),100*target
  end.
  t =. t+duration
  fl =. target
  length =. length+len
 end.
 segments;length
)
position =: 4 : '(5 6 7{x)+(8 9 10{x)*(y-3{x)'
segment_at =: 4 : 0
 for_i. i.#x do.
  s =. i{x
  if. (y>:3{s)*.y<4{s do. i return. end.
 end.
 _1
)
arrival =: 3 : '4{ {:y'
track =: 3 : '360|((12 o.(9{y)j.(8{y))*180)%3.141592653589793'
