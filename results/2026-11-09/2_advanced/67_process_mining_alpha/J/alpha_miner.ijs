triangles =: 3 : 0
 counts =. (NA,NA)$0
 for_item. y do.
  'trace weight' =. >item
  for_i. i.0>.(#trace)-2 do.
   a =. i{trace
   b =. (i+1){trace
   if. (a~:b)*.a=(i+2){trace do. counts =. (weight+(<a,b){counts)(<a,b)}counts end.
  end.
 end.
 counts
)
valid_pair =: 4 : 0
 'causal unrelated' =. x
 'a b' =. y
 (*./,(<a;b){causal)*.(*./,(<a;a){unrelated)*.*./,(<b;b){unrelated
)
alpha_relation =: 4 : 0
 f =. follows y
 tri =. triangles y
 causal =. (f>0)*.0=|:f
 if. x do. causal =. (f>0)*.((0=|:f)+.(tri>0)*.(|:tri)>0) end.
 unrelated =. (f=0)*.(|:f)=0
 symbols =. causal+2*((-.causal)*.|:causal)
 parallel =. (f>0)*.(|:f)>0
 if. x do. parallel =. parallel*.-.(tri>0)*.(|:tri)>0 end.
 symbols =. 3(I.,parallel)} ,symbols
 (NA,NA)$symbols
)
discover =: 3 : 0
 'log tids plus' =. y
 f =. follows log
 tri =. triangles log
 causal =. (f>0)*.(0=|:f)
 if. plus do. causal =. (f>0)*.((0=|:f)+.(tri>0)*.(|:tri)>0) end.
 unrelated =. (f=0)*.(|:f)=0
 pairs =. 0$a:
 for_a. tids do. for_b. tids do.
  pair =. (,a);,b
  if. (causal;unrelated)valid_pair pair do. pairs =. pairs,<pair end.
 end. end.
 i =. 0
 while. i<#pairs do.
  'a b' =. i{::pairs
  for_t. tids do.
   for_side. i.2 do.
    aa =. a
    bb =. b
    if. side=0 do. aa =. /:~~.a,t else. bb =. /:~~.b,t end.
    pair =. aa;bb
    if. -.(<pair)e.pairs do. if. (causal;unrelated)valid_pair pair do. pairs =. pairs,<pair end. end.
   end.
  end.
  i =. i+1
 end.
 maximal =. 0$a:
 for_pair. pairs do.
  'a b' =. >pair
  max =. 1
  for_t. tids do.
   if. -.t e.a do. if. (causal;unrelated)valid_pair (/:~a,t);b do. max =. 0 end. end.
   if. -.t e.b do. if. (causal;unrelated)valid_pair a;/:~b,t do. max =. 0 end. end.
  end.
  if. max do. maximal =. maximal,pair end.
 end.
 maximal =. /:~maximal
 starts =. ends =. i.0
 for_item. log do. trace =. 0{::>item
 starts =. starts,{.trace
 ends =. ends,{:trace end.
 starts =. /:~~.starts
 ends =. /:~~.ends
 places =. <'start'
 for_i. 1+i.#maximal do. places =. places,<'p',str i end.
 places =. places,<'end'
 ins =. outs =. (#tids)$<i.0
 for_j. i.#tids do.
  t =. j{tids
  input =. output =. i.0
  if. t e.starts do. input =. ,0 end.
  if. t e.ends do. output =. ,1+#maximal end.
  for_i. i.#maximal do.
   'a b' =. i{::maximal
   if. t e.a do. output =. output,i+1 end.
   if. t e.b do. input =. input,i+1 end.
  end.
  ins =. (< /:~input)j}ins
  outs =. (< /:~output)j}outs
 end.
 net =. places;tids;ins;outs;0;(1+#maximal)
 net;maximal;(#pairs);(+/,(<tids;tids){causal);(plus alpha_relation log);tri
)
