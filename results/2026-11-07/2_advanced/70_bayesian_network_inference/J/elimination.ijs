plan =: 3 : 0
 'factors eliminate given' =. y
 graph =. (NV,NV)$0
 live =. i.0
 for_f. factors do.
  scope =. 0{::>f
  live =. ~.live,scope
  for_v. scope do. graph =. 1(<v;scope-.v)}graph end.
 end.
 records =. 0$a:
 while. #eliminate do.
  keys =. 0 3$0
  for_v. eliminate do.
   ns =. I.v{graph
   fill =. 0
   for_i. i.#ns do.
    for_j. (i+1)+i.((#ns)-i)-1 do. fill =. fill+-. (<(i{ns),j{ns){graph end.
   end.
   keys =. keys,fill,(#ns),v
  end.
  if. given do. v =. {.Order#~Order e.eliminate
  else. v =. 2{({./:keys){keys end.
  key =. (eliminate i.v){keys
  ns =. I.v{graph
  scope =. /:~v,ns
  records =. records,<v;(0{key);scope;*/scope{K
  for_a. ns do. graph =. 1(<a;ns-.a)}graph end.
  graph =. 0 v}graph
  graph =. 0(<a:;v)}graph
  eliminate =. eliminate-.v
 end.
 records
)
execute =: 3 : 0
 'factors records maximize evidence' =. y
 products =. 0$a:
 for_rec. records do.
  v =. 0{::>rec
  selected =. i.0
  for_i. i.#factors do. if. v e.0{::i{::factors do. selected =. selected,i end. end.
  f =. product selected{factors
  products =. products,<f
  factors =. ((i.#factors)-.selected){factors
  factors =. factors,<(v;maximize)collapse f
 end.
 answer =. product factors
 row =. NV$0
 'ev es' =. evidence
 row =. es ev}row
 if. maximize do.
  for_i. |.i.#records do.
   v =. 0{::i{::records
   f =. i{::products
   vals =. i.0
   for_s. i.v{K do. vals =. vals,f factor_value s v}row end.
   row =. (vals i.>./vals)v}row
  end.
 end.
 answer;row
)
initial_factors =: 3 : 0
 'relevant ev es' =. y
 fs =. 0$a:
 for_v. relevant do. fs =. fs,<(ev;es)reduce_factor cpt_factor v end.
 fs
)
infer =: 3 : 0
 'q ev es given maximize' =. y
 relevant =. i.NV
 if. -.maximize do. relevant =. ancestors /:~~.q,ev end.
 fs =. initial_factors relevant;ev;es
 elim =. relevant-.q,ev
 pl =. plan fs;elim;given
 result =. execute fs;pl;maximize;(ev;es)
 f =. 0{::result
 vals =. 1{::f
 z =. sum vals
 if. maximize do. z =. {.vals else. vals =. vals%z end.
 relevant;elim;pl;(0{::f);vals;z;1{::result
)
