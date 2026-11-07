search_header=:3 :0
 'name quoted'=.y
  if. quoted  do. paths=.(<name),<'include/',name  else. paths=.,<'include/',name  end.
  for_path. paths  do.  if. 0<#1!:0 <'input/',>path  do. >path  return.  end.  end.
 ''
)
detect_guard=:3 :0
 ls=.0$a:
  for_l. y  do.  if. #tokens__l  do. ls=.ls,l  end.  end.
  if. 0=#ls  do. '' return.  end.
 first=.{.ls
  last=.{:ls
 a=.spellings tokens__first
  b=.spellings tokens__last
  if. (3~:#a)+.-.('#';'ifndef')-:2{.a  do. '' return.  end.
 t=.2{tokens__first
  if. -.kind__t-:'identifier' do. '' return.  end.
  if. -.('#';'endif')-:b  do. '' return.  end.
 depth=.0
  for_i. i.#ls  do. l=.i{ls
  names=.spellings tokens__l
   if. 1<#names  do.
    if. '#'-:0{::names  do.
    directive=.1{::names
     if. (depth=1)*.(<directive)e.(<;._1 ' ','elif elifdef elifndef else') do. '' return.  end.
     if. (<directive)e.(<;._1 ' ','if ifdef ifndef') do. depth=.depth+1 elseif. directive-:'endif' do. depth=.depth-1 end.
     if. (depth=0)*.i< <:#ls  do. '' return.  end.
    end.
   end.
  end.
 spell__t
)
get_file=:3 :0
 i=.FileNames i.<y
  if. i<#FileNames  do. i{Files  return.  end.
 f=.cocreate''
 path__f=:y
 raw=.1!:1 <'input/',y
 lines__f=:lex_source raw
  physical__f=:+/raw=LF
  guard__f=:detect_guard lines__f
 entered__f=:skipped__f=:output__f=:skippedlines__f=:once__f=:0
 FileNames=:FileNames,<y
  Files=:Files,f
 f
)
read_header=:3 :0
 ts=.y
  if. 0=#ts  do. '';'';0;0 return.  end.
 t=.{.ts
  if. (<kind__t)e.'string';'header' do. (}.}:spell__t);spell__t;1;(kind__t-:'string') return.  end.
  if. spell__t-:'<' do.
  p=.1
   while. p<#ts  do. t=.p{ts
   if. spell__t-:'>' do.  break.  end.
  p=.p+1 end.
   if. p=#ts  do. error 'missing terminating > character'
  13!:8]3 end.
  name=.render (p-1){.}.ts
  name;('<',name,'>');(p+1);0
  else. '';'';0;0 end.
)
