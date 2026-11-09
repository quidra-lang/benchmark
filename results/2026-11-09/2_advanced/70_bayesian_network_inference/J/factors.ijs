factor_value =: 4 : 0
 'scope values' =. x
 if. 0=#scope do. {.values else. ((scope{K)#.scope{y){values end.
)
cpt_factor =: 3 : 0
 scope =. /:~~.y,y{::Parents
 vals =. i.0
 for_a. assignments scope do.
  row =. NV$0
  row =. a scope}row
  vals =. vals,y probability row
 end.
 scope;vals
)
reduce_factor =: 4 : 0
 'ev es' =. x
 'scope values' =. y
 free =. scope-.ev
 out =. i.0
 for_a. assignments free do.
  row =. NV$0
  row =. es ev}row
  row =. a free}row
  out =. out,y factor_value row
 end.
 free;out
)
product =: 3 : 0
 scope =. i.0
 for_f. y do. scope =. /:~~.scope,0{::>f end.
 values =. i.0
 for_a. assignments scope do.
  row =. NV$0
  row =. a scope}row
  value =. 1.0
  for_f. y do. value =. value*(>f)factor_value row end.
  values =. values,value
 end.
 scope;values
)
collapse =: 4 : 0
 'v maximize' =. x
 'scope values' =. y
 free =. scope-.v
 out =. i.0
 for_a. assignments free do.
  row =. NV$0
  row =. a free}row
  vals =. i.0
  for_s. i.v{K do. vals =. vals,y factor_value s v}row end.
  if. maximize do. value =. >./vals else. value =. sum vals end.
  out =. out,value
 end.
 free;out
)
