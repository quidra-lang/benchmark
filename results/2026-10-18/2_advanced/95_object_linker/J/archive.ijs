read_archive=:3 :0
 members=.0$a:
 lines=.readlines 'input/',y
 p=.0
  while. p<#lines  do.
  header=.words p{::lines
  p=.p+1
  start=.p
   while. -.'end'-:p{::lines  do. p=.p+1  end.
  o=.(y,'(',(1{::header),')') parse_object ((1+p)-start){.start}.lines
  exports__o=:2}.header
  loaded__o=:0
  members=.members,o
  p=.p+1
  end.
 members
)
get_archive=:3 :0
 i=.ArchiveNames i.<y
  if. i=#ArchiveNames  do.
  ArchiveNames=:ArchiveNames,<y
  Archives=:Archives,<read_archive y
  end.
 i{::Archives
)
scan_archive=:3 :0
 members=.get_archive y
 count=.0
 again=.1
  while. again  do.
  again=.0
   for_o. members  do.
    if. loaded__o  do.  continue.  end.
   reason=.''
    for_e. exports__o  do.  if. is_undefined >e  do. reason=.>e
   break.  end.  end.
    if. 0=#reason  do.  continue.  end.
   ref=.'*entry*'
    for_old. Objects  do.
    found=.0
     for_s. symbols__old  do.
      if. (name__s-:reason)*.(binding__s-:'global')*.status__s-:'undef'  do. ref=.name__old
  found=.1
   break.  end.
     end.
     if. found  do.  break.  end.
    end.
   Extractions=:Extractions,<'member ',name__o,' ',ref,' ',reason
   load_object o
   loaded__o=:1
   count=.count+1
   again=.1
   end.
  end.
 count
)
