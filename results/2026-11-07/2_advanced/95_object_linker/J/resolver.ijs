find_resolution=:3 :0
 i=.GlobalNames i.<y
  if. i=#GlobalNames  do. a: else. i{Resolutions  end.
)
is_defined=:3 :0
  if. (<y)e.ScriptNames  do. 1  return.  end.
  for_o. Objects  do.
   for_s. symbols__o  do.
    if. (name__s-:y)*.(-.binding__s-:'local')*.-.status__s-:'undef'  do. 1  return.  end.
   end.
  end.
 0
)
is_undefined=:3 :0
  if. is_defined y  do. 0  return.  end.
  if. Entry-:y  do. 1  return.  end.
  for_o. Objects  do.
   for_s. symbols__o  do.
    if. (name__s-:y)*.(binding__s-:'global')*.status__s-:'undef'  do. 1  return.  end.
   end.
  end.
 0
)
resolve_all=:3 :0
 GlobalNames=:ScriptNames
  for_o. Objects  do.  for_s. symbols__o  do.  if. -.binding__s-:'local'  do. GlobalNames=:GlobalNames,<name__s  end.  end.  end.
 GlobalNames=:/:~~.GlobalNames
 Resolutions=:0$a:
  for_n. GlobalNames  do.
  n=.>n
  r=.cocreate''
  name__r=:n
  strong__r=:weak__r=:common__r=:refs__r=:0$a:
  referrers__r=:0$a:
  definition__r=:a:
  definer__r=:'-'
  size__r=:0
  alignment__r=:1
  live__r=:0
  address__r=:0
   for_o. Objects  do.
    for_s. symbols__o  do.
     if. (name__s-:n)*.-.binding__s-:'local'  do.
      select. status__s
      case. 'undef'  do. refs__r=:refs__r,s
  referrers__r=:~.referrers__r,<name__o
      case. 'common'  do. common__r=:common__r,s
      case.  do.  if. binding__s-:'global'  do. strong__r=:strong__r,s  else. weak__r=:weak__r,s  end.
      end.
     end.
    end.
   end.
   if. (<n)e.ScriptNames  do. kind__r=:'script'
  definer__r=:'*script*'
  live__r=:1
   elseif. #strong__r  do. kind__r=:'global'
  definition__r=:{.strong__r
   elseif. #common__r  do.
   kind__r=:'common'
    for_s. common__r  do. size__r=:size__r>.size__s
  alignment__r=:alignment__r>.alignment__s  end.
    for_s. common__r  do.  if. size__s=size__r  do. o=.owner__s
  definer__r=:name__o
   break.  end.  end.
   elseif. #weak__r  do. kind__r=:'weak'
  definition__r=:{.weak__r
   else.
   kind__r=:'weakundef'
    for_s. refs__r  do.  if. binding__s-:'global'  do. kind__r=:'undefined' end.  end.
   end.
   if. (<kind__r)e.'global';'weak'  do. s=.definition__r
  o=.owner__s
  definer__r=:name__o  end.
  Resolutions=:Resolutions,r
  end.
)
reloc_target=:3 :0
 s=.symbol__y
  if. binding__s-:'local'  do. section__s  return.  end.
 r=.find_resolution name__s
  if. (<kind__r)e.'global';'weak'  do. s=.definition__r
  section__s
  elseif. kind__r-:'common'  do. r
  else. a: end.
)
symbol_value=:3 :0
 s=.y
  if. -.binding__s-:'local'  do.
  r=.find_resolution name__s
   select. kind__r
   case. 'undefined'  do. _1  return.
   case. 'weakundef'  do. 0  return.
   case. 'script';'common'  do. address__r  return.
   case.  do. s=.definition__r
   end.
  end.
 t=.section__s
  if. stringsection name__t  do. address__t+offset__s{mapping__t  else. address__t+offset__s  end.
)
