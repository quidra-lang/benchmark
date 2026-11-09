readlines=:3 : '<;._2 (1!:1 <y)'
valid_filename=:3 :0
  if. 0=#y  do. 0 return.  end.
 ('.'~:{.y)*.*./y e.letters,digits,'._-'
)
assignment_arg=:3 :0
 i=.y i.'='
 name=.i{.y
  if. i=#y  do. 0;'';'' return.  end.
 valid=.0
  if. #name  do. valid=.(({.name)e.letters,'_')*.*./name e.namechars  end.
 valid;name;(i+1)}.y
)
parse_arguments=:3 :0
 Options=:Operands=:0$a:
  InputStats=:i.0
  InputNames=:0$a:
  for_line. y  do.
  line=.>line
   if. '-F '-:3{.line  do. Options=:Options,<'FS';3}.line
   elseif. '-v '-:3{.line  do. 'yes name val'=.assignment_arg 3}.line
  Options=:Options,<name;val
   else.
   'yes name val'=.assignment_arg line
    if. yes  do. Operands=:Operands,<0;name;val
    else. InputNames=:InputNames,<line
  InputStats=:InputStats,0
  Operands=:Operands,<1;line;<:#InputNames  end.
   end.
  end.
)
stream_output=:4 :0
 'name append'=.x
  text=.y
  if. ( -.valid_filename name)+.(<name)e.'stdout.txt';'stats.txt' do. runtime_error 'invalid output file name' end.
 i=.OutputNames i.<name
  if. i=#OutputNames  do. OutputNames=:OutputNames,<name
  OutputContents=:OutputContents,<''
  OutputOpen=:OutputOpen,0
  OutputCounts=:OutputCounts,0 end.
  if. -.i{OutputOpen  do.
   if. -.append  do. OutputContents=:(<'')i}OutputContents  end.
  OutputOpen=:1 i}OutputOpen
  end.
 OutputContents=:(<(i{::OutputContents),text)i}OutputContents
 OutputCounts=:(1+i{OutputCounts)i}OutputCounts
)
getline_stream=:3 :0
 name=.y
  i=.GetNames i.<name
  if. i=#GetNames  do. GetNames=:GetNames,<name
  GetOpen=:GetOpen,0
  GetPositions=:GetPositions,0
  GetCounts=:GetCounts,0
  GetExists=:GetExists,0
  GetLines=:GetLines,<0$a: end.
  if. -.i{GetOpen  do.
  exists=.valid_filename name
   if. exists  do. exists=.0<#1!:0 <'input/',name  end.
   if. -.exists  do. _1;'' return.  end.
  GetExists=:1 i}GetExists
  GetOpen=:1 i}GetOpen
  GetPositions=:0 i}GetPositions
  GetLines=:(<readlines 'input/',name)i}GetLines
  end.
 p=.i{GetPositions
  ls=.i{::GetLines
  if. p=#ls  do. 0;'' return.  end.
 GetPositions=:(p+1)i}GetPositions
 GetCounts=:(1+i{GetCounts)i}GetCounts
 1;p{::ls
)
close_stream=:3 :0
 closed=.0
 i=.OutputNames i.<y
  if. i<#OutputNames  do.  if. i{OutputOpen  do. closed=.1
  OutputOpen=:0 i}OutputOpen  end.  end.
 i=.GetNames i.<y
  if. i<#GetNames  do.  if. i{GetOpen  do. closed=.1
  GetOpen=:0 i}GetOpen  end.  end.
  if. closed  do. 0 else. _1 end.
)
