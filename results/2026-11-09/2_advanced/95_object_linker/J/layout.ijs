align=:4 : 'y*>.x%y'
assign_output=:3 :0
  for_o. OutSections  do.  if. name__o belongs y  do. o  return.  end.  end.
 a:
)
component=:3 :0
 c=.cocreate''
 kind__c=:y
 size__c=:0
 alignment__c=:1
 bytes__c=:i.0
 source__c=:a:
 name__c=:''
 c
)
build_components=:3 :0
  for_out. OutSections  do.
  secs=.0$a:
  priority=.i.0
   for_s. Sections  do.
    if. live__s*.out-:output__s  do.
    secs=.secs,s
    p=.65536
     if. (<name__out)e.Sorts  do.  if. -.name__s-:name__out  do. p=.num (1+#name__out)}.name__s  end.  end.
    priority=.priority,p
    end.
   end.
   if. (<name__out)e.Sorts  do. secs=.( /:priority){secs  end.
  strings=.0$a:
   for_s. secs  do.  if. stringsection name__s  do. strings=.strings,s  end.  end.
  merged=.a:
   if. #strings  do.
   merged=.component 'merged'
   sources__merged=:strings
   count__merged=:0
   unique__merged=:0
   saved__merged=:0
   seen=.0$a:
   offsets=.i.0
    for_s. strings  do.
    mapping__s=:(1+size__s)$_1
    p=.0
     while. p<size__s  do.
     len=.1+(p}.bytes__s)i.0
     str=.len{.p}.bytes__s
     i=.seen i.<str
      if. i=#seen  do. seen=.seen,<str
  offsets=.offsets,#bytes__merged
  bytes__merged=:bytes__merged,str  end.
     mapping__s=:(i{offsets) p}mapping__s
     p=.p+len
     count__merged=:count__merged+1
     end.
    saved__merged=:saved__merged+size__s
    end.
   size__merged=:#bytes__merged
   unique__merged=:#seen
   saved__merged=:saved__merged-size__merged
   end.
  components__out=:0$a:
  inserted=.0
   for_s. secs  do.
    if. stringsection name__s  do.
     if. -.inserted  do. components__out=:components__out,merged
  inserted=.1  end.
    else.
    c=.component 'input'
    source__c=:s
    size__c=:size__s
    alignment__c=:alignment__s
    components__out=:components__out,c
    end.
   end.
   if. name__out-:'.bss'  do.
   rs=.0$a:
  als=.i.0
    for_r. Resolutions  do.  if. (kind__r-:'common')*.live__r  do. rs=.rs,r
  als=.als,-alignment__r  end.  end.
    for_r. ( /:als){rs  do.
    c=.component 'common'
    source__c=:r
  size__c=:size__r
  alignment__c=:alignment__r
    components__out=:components__out,c
    end.
   end.
   for_pair. Veneers  do.
   'o n'=.>pair
    if. o-:out  do. c=.component 'veneer'
  name__c=:n
  size__c=:8
  alignment__c=:4
  components__out=:components__out,c  end.
   end.
  end.
)
place_segments=:3 :0
  for_g. Segments  do.
  cursor=.base__g
  filesz__g=:0
   for_out. outputs__g  do.
   al=.1
    for_c. components__out  do. al=.al>.alignment__c  end.
   alignment__out=:al
   cursor=.cursor align al
   address__out=:cursor
    for_c. components__out  do.
    cursor=.cursor align alignment__c
    address__c=:cursor
     select. kind__c
     case. 'input'  do. s=.source__c
  address__s=:cursor
     case. 'common'  do. r=.source__c
  address__r=:cursor
     case. 'merged'  do.  for_s. sources__c  do. address__s=:cursor  end.
     end.
    cursor=.cursor+size__c
    end.
   size__out=:cursor-address__out
    if. -.nobits name__out  do. filesz__g=:cursor-base__g  end.
   end.
  memsz__g=:cursor-base__g
  paddr__g=:base__g
  used__g=:memsz__g
  end.
)
