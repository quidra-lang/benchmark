stringize=:4 :0
 hash=.x
  raw=.y
  result=.'"'
  for_i. i.#raw  do.
  t=.i{raw
   if. (i>0)*.space__t  do. result=.result,' ' end.
  spell=.spell__t
   if. (<kind__t)e.'string';'character' do. spell=.spell rplc '\';'\\';'"';'\"' end.
  result=.result,spell
  end.
 token 'string';(result,'"');line__hash;space__hash
)
paste=:4 :0
 l=.x
  r=.y
  if. kind__l-:'marker' do. t=.clone_token r
  space__t=:space__l
  ,t  return.  end.
  if. kind__r-:'marker' do. ,l  return.  end.
 spell=.spell__l,spell__r
 'good kind'=.single_token spell
  if. good  do.
  t=.token kind;spell;line__l;space__l
  hide__t=:hide__l-.hide__l-.hide__r
  ,t
  else.
  error 'pasting "',spell__l,'" and "',spell__r,'" does not give a valid preprocessing token'
  t=.clone_token r
  space__t=:0
  l,t
  end.
)
collect_arguments=:4 :0
 m=.x
  input=.y
  args=.0$a:
  raw=.0$a:
  separators=.0$a:
  depth=.0
  p=.1
  while. p<#input  do.
  t=.p{input
  spell=.spell__t
   if. (spell-:')')*.depth=0 do. args=.args,<raw
   break.  end.
   if. (spell-:',')*.depth=0 do. args=.args,<raw
  raw=.0$a:
  separators=.separators,t
   else.
    if. spell-:'(' do. depth=.depth+1 elseif. spell-:')' do. depth=.depth-1 end.
   raw=.raw,t
   end.
  p=.p+1
  end.
  if. p=#input  do. error 'unterminated argument list invoking macro "',name__m,'"'
  a: return.  end.
 k=.#args
  n=.(#params__m)-variadic__m
  if. (n=0)*.(-.variadic__m)*.(k=1)*.0=#0{::args  do. args=.0$a:
  k=.0 end.
  if. k<n  do. error 'macro "',name__m,'" requires ',(dec n),' arguments, but only ',(dec k),' given'
  a: return.  end.
  if. (k>n)*.-.variadic__m  do. error 'macro "',name__m,'" passed ',(dec k),' arguments, but takes just ',dec n
  a: return.  end.
  if. variadic__m  do.
  variadic=.0$a:
   for_i. n+i.k-n  do.
    if. i>n  do. variadic=.variadic,(i-1){separators  end.
   variadic=.variadic,i{::args
   end.
  args=.(n{.args),<variadic
  end.
 args;(p{input);(p+1)}.input
)
substitute=:3 :0
 'm original hidden rawargs'=.y
 replacement=.clone_tokens replacement__m
  items=.0$a:
  cache=.(#params__m)$a:
  p=.0
  while. p<#replacement  do.
  t=.p{replacement
  p=.p+1
  spell=.spell__t
   if. function__m*.spell-:'#' do.
   param=.p{replacement
  p=.p+1
  index=.params__m i.<spell__param
   items=.items,<,t stringize index{::rawargs
   elseif. spell-:'##' do. items=.items,<'##'
   elseif. (kind__t-:'identifier')*.(<spell)e.params__m  do.
   i=.params__m i.<spell
   adjacent=.0
    if. p>1 do. previous=.(p-2){replacement
  adjacent=.spell__previous-:'##' end.
    if. p<#replacement  do. next=.p{replacement
  adjacent=.adjacent+.spell__next-:'##' end.
    if. adjacent  do. arg=.i{::rawargs
    else.
     if. a:-:i{cache  do. cache=:(<expand i{::rawargs)i}cache  end.
    arg=.i{::cache
    end.
   arg=.clone_tokens arg
    if. #arg  do. first=.{.arg
  space__first=:space__t  else. arg=.,token 'marker';'';line__t;space__t  end.
   items=.items,<arg
   else. items=.items,<,t  end.
  end.
 result=.0$a:
  p=.0
  while. p<#items  do.
  item=.p{::items
  p=.p+1
   if. item-:'##' do.
   right=.p{::items
  p=.p+1
    if. right-:'##' do. right=.,token 'punctuator';'##';line__original;0 end.
   l=.{:result
  result=.}:result
   result=.result,(l paste {.right),}.right
   else. result=.result,item  end.
  end.
 output=.0$a:
  space=.0
  for_t. result  do.
   if. kind__t-:'marker' do. space=.space+.space__t
   continue.  end.
  space__t=:space__t+.space
  space=.0
  line__t=:line__original
  hide__t=:~.hide__t,hidden
  output=.output,t
  end.
  if. #output  do. t=.{.output
  space__t=:space__original  end.
 output
)
expand=:3 :0
 input=.clone_tokens y
  result=.0$a:
  while. #input  do.
  t=.{.input
  input=.}.input
  name=.spell__t
   if. (-.kind__t-:'identifier')+.(<name)e.hide__t  do. result=.result,t
   continue.  end.
   if. (<name)e.Builtins  do.
   i=.Builtins i.<name
  BuiltinCounts=:(1+i{BuiltinCounts)i}BuiltinCounts
    if. name-:'__COUNTER__' do. spell=.dec Counter
  Counter=:Counter+1
  kind=.'number'
    elseif. name-:'__LINE__' do. spell=.dec line__t+offset__Current
  kind=.'number'
    else. spell=.'"',display__Current,'"'
  kind=.'string' end.
   result=.result,token kind;spell;line__t;space__t
    continue.
   end.
  m=.find_macro name
   if. m-:a: do. result=.result,t
   continue.  end.
  At=:line__t
  hidden=.~.hide__t,<name
  args=.0$a:
   if. function__m  do.
    if. 0=#input  do. result=.result,t
   continue.  end.
   next=.{.input
    if. -.spell__next-:'(' do. result=.result,t
   continue.  end.
   collected=.m collect_arguments input
    if. collected-:a: do. result=.result,t
   continue.  end.
   'args close input'=.collected
   hidden=.~.(hide__t-.hide__t-.hide__close),<name
   end.
  replacement=.substitute m;t;hidden;args
  expanded__m=:expanded__m+1
   if. (0=#replacement)*.space__t*.0<#input  do. next=.{.input
  space__next=:1 end.
  input=.replacement,input
  end.
 result
)
