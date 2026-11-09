Builtins=:(<;._1 ' ','__COUNTER__ __FILE__ __LINE__')
find_macro=:3 :0
 i=.MacroNames i.<y
  if. i=#MacroNames  do. a: else. i{Macros  end.
)
name_error=:4 :0
 directive=.x
  ts=.y
  if. 0=#ts  do. 'no macro name given in #',directive,' directive' return.  end.
 t=.{.ts
  if. -.kind__t-:'identifier' do. 'macro names must be identifiers' return.  end.
  if. spell__t-:'defined' do. '"defined" cannot be used as a macro name' return.  end.
  if. (<spell__t)e.Builtins  do.
   if. directive-:'define' do. 'cannot redefine builtin macro "',spell__t,'"' else. 'cannot undefine builtin macro "',spell__t,'"' end.
  else. '' end.
)
definition_error=:3 :0
 error y
 13!:8]3
)
parse_definition=:3 :0
 ts=.clone_tokens y
 message=.'define'name_error ts
  if. #message  do. definition_error message  end.
 first=.{.ts
 m=.cocreate''
 name__m=:spell__first
  function__m=:0
  variadic__m=:0
  params__m=:0$a:
  expanded__m=:tested__m=:0
 p=.1
  if. p<#ts  do. t=.p{ts
   if. (spell__t-:'(')*.-.space__t  do.
   function__m=:1
  p=.p+1
  need=.1
    while. 1 do.
     if. p=#ts  do. definition_error 'missing '')'' in macro parameter list' end.
    t=.p{ts
  p=.p+1
     if. (spell__t-:')')*.need*.0=#params__m  do.  break.  end.
     if. need  do.
     n=.spell__t
      if. n-:'...' do. n=.'__VA_ARGS__'
  variadic__m=:1
      elseif. -.kind__t-:'identifier' do. definition_error 'expected parameter name, found "',n,'"'
      elseif. n-:'__VA_ARGS__' do. definition_error '"__VA_ARGS__" can only appear in the expansion of a variadic macro'
      elseif. (<n)e.params__m  do. definition_error 'duplicate macro parameter "',n,'"' end.
     params__m=:params__m,<n
  need=.0
     else.
      if. spell__t-:')' do.  break.  end.
      if. variadic__m  do. definition_error 'expected '')'' after "...", found "',spell__t,'"' end.
      if. -.spell__t-:',' do. definition_error 'expected '','' or '')'', found "',spell__t,'"' end.
     need=.1
     end.
    end.
   end.
  end.
 replacement__m=:p}.ts
  if. name__m-:'__VA_ARGS__' do. definition_error '"__VA_ARGS__" can only appear in the expansion of a variadic macro' end.
 rs=.replacement__m
  if. #rs  do.
  t=.{.rs
  space__t=:0
   if. (< '##')e.spellings ({.rs),{:rs  do. definition_error '''##'' cannot appear at either end of a macro expansion' end.
  end.
  for_i. i.#rs  do.
  t=.i{rs
   if. (spell__t-:'__VA_ARGS__')*.-.variadic__m  do. definition_error '"__VA_ARGS__" can only appear in the expansion of a variadic macro' end.
   if. function__m*.spell__t-:'#' do.
    if. i+1=#rs  do. definition_error '''#'' is not followed by a macro parameter' end.
   u=.(i+1){rs
    if. -.(kind__u-:'identifier')*.(<spell__u)e.params__m  do. definition_error '''#'' is not followed by a macro parameter' end.
   end.
  end.
 m
)
signature=:3 :0
 m=.y
  if. -.function__m  do. name__m  return.  end.
 ps=.params__m
  if. variadic__m  do. ps=:(<'...')(<:#ps)}ps  end.
 name__m,'(',(', 'join ps),')'
)
identical_definition=:4 :0
 a=.x
  b=.y
  if. (function__a~:function__b)+.(variadic__a~:variadic__b)+.-.params__a-:params__b  do. 0 return.  end.
  if. -.(spellings replacement__a)-:spellings replacement__b  do. 0 return.  end.
  for_i. i.#replacement__a  do. s=.i{replacement__a
  t=.i{replacement__b
   if. space__s~:space__t  do. 0 return.  end.  end.
 1
)
