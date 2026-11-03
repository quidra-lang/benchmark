manoeuvres =: 3 : 0
 out =. 'level_up';'level_down';'speed_down'
 for_d. 60*1+i.<.(pn 'max_delay')%60 do. out =. out,<'delay_',str d end.
 out
)
apply_manoeuvre =: 4 : 0
 plan =. y
 select. x
 case. 'level_up' do. plan =. (<10+7{::plan)7}plan
 case. 'level_down' do. plan =. (<_10+7{::plan)7}plan
 case. 'speed_down' do. plan =. (<<.(9*8{::plan)%10)8}plan
 case. do. plan =. (<(6{::plan)+num 6}.x)6}plan
 end.
 levels =. (3{::plan),((2{"1 5{::plan)#~0<:2{"1 5{::plan)
 levels =. levels+7{::plan
 'lo hi' =. pv 'levels'
 ok =. (*./levels>:lo)*.*./levels<:hi
 typ =. 1{::plan
 ok =. ok*.(8{::plan)>:(<typ,2){Types
 ok;plan
)
priority =: 4 : 0
 tx =. (2{::x)+6{::x
 ty =. (2{::y)+6{::y
 if. tx=ty do. 1={./:(<0{::x),<0{::y else. tx>ty end.
)
