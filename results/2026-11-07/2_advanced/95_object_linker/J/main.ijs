ScriptPath=: >{:4!:3''
SourceDirectory=: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'object_parser.ijs'
load SourceDirectory,'archive.ijs'
load SourceDirectory,'resolver.ijs'
load SourceDirectory,'layout.ijs'
load SourceDirectory,'relocator.ijs'
load_object=:3 :0
 o=.y
  for_group. comdats__o  do.
  'sig names'=.>group
  i=.ComdatNames i.<sig
   if. i=#ComdatNames  do.
   ComdatNames=:ComdatNames,<sig
   ComdatKeepers=:ComdatKeepers,o
   ComdatDiscards=:ComdatDiscards,<0$a:
   else.
   ds=.i{::ComdatDiscards
   ComdatDiscards=:(<ds,<name__o)i}ComdatDiscards
    for_s. sections__o  do.  if. (<name__s)e.names  do. discard__s=:'comdat' end.  end.
   end.
  end.
  for_s. symbols__o  do.
   if. status__s-:'defined'  do.
   t=.section__s
    if. (discard__t-:'comdat')*.-.binding__s-:'local'  do. status__s=:'undef'
  section__s=:a: end.
   end.
   if. status__s-:'undef'  do.
   n=.name__s
    if. (<n)e.Wraps  do. name__s=:'__wrap_',n
    elseif. '__real_'-:7{.n  do.  if. (<7}.n)e.Wraps  do. name__s=:7}.n  end.  end.
   end.
  end.
 Objects=:Objects,o
 Sections=:Sections,sections__o
)
collect_live=:3 :0
  for_s. Sections  do.
   if. #discard__s  do.  continue.  end.
  output__s=:assign_output name__s
   if. output__s-:a:  do. discard__s=:'orphan' else. live__s=: -.GC  end.
  end.
  for_r. Resolutions  do.  if. kind__r-:'common'  do. live__r=: -.GC  end.  end.
  if. -.GC  do.  return.  end.
 queue=.0$a:
  for_s. Sections  do.
  o=.output__s
   if. -.o-:a:  do.  if. (<name__o)e.Keeps  do. queue=.queue,s  end.  end.
  end.
 r=.find_resolution Entry
  if. -.r-:a:  do.
   if. (<kind__r)e.'global';'weak'  do. v=.definition__r
  queue=.queue,section__v
   elseif. kind__r-:'common'  do. queue=.queue,r  end.
  end.
  while. #queue  do.
  s=.{.queue
  queue=.}.queue
   if. live__s  do.  continue.  end.
  live__s=:1
   if. s e.Sections  do.
   o=.owner__s
    for_re. relocs__o  do.  if. s-:section__re  do.
    t=.reloc_target re
     if. -.t-:a:  do.  if. t e.Sections  do.  if. 0=#discard__t  do. queue=.queue,t  end.  else. queue=.queue,t  end.  end.
    end.  end.
   end.
  end.
  for_s. Sections  do.  if. (0=#discard__s)*.-.live__s  do. discard__s=:'gc' end.  end.
)
far_calls=:3 :0
 far=.0$a:
  for_o. Objects  do.  for_r. relocs__o  do.
  s=.section__r
  v=.symbol__r
   if. live__s*.(type__r-:'CALL24')*.-.binding__v-:'local'  do.
   res=.find_resolution name__v
    if. (<kind__res)e.'global';'weak'  do.
    delta=.(symbol_value v)+addend__r-(address__s+offset__r)
     if. (delta<_33554432)+.delta>:33554432  do. far=.far,r  end.
    end.
   end.
  end.  end.
 far
)
script_tokens=:3 :0
 r=.0$a:
  p=.0
  while. p<#y  do.
  c=.p{y
   if. c=' '  do. p=.p+1
   continue.  end.
   if. c e.'(),+-'  do. r=.r,<,c
  p=.p+1
   continue.  end.
  start=.p
   while. p<#y  do.  if. (p{y)e.' (),+-'  do.  break.  end.
  p=.p+1  end.
  r=.r,<(p-start){.start}.y
  end.
 r
)
script_term=:3 :0
 t=.EP{::ET
  EP=:EP+1
  if. t-:'('  do. v=.script_expr''
  EP=:EP+1
  v  return.  end.
  if. ({.t)e.'0123456789'  do. num t  return.  end.
  if. EP<#ET  do.
   if. '('-:EP{::ET  do.
   EP=:EP+1
    if. t-:'align'  do. a=.script_expr''
  EP=:EP+1
  b=.script_expr''
  EP=:EP+1
  a align b  return.  end.
   name=.EP{::ET
  EP=:EP+2
   out=.(OutputNames i.<name){OutSections
   g=.segment__out
    select. t
    case. 'start'  do. address__out
    case. 'end'  do. address__out+size__out
    case. 'size'  do. size__out
    case. 'loadaddr'  do. paddr__g+address__out-base__g
    end.
    return.
   end.
  end.
 r=.find_resolution t
 address__r
)
script_expr=:3 :0
 v=.script_term''
  while. EP<#ET  do.
  op=.EP{::ET
   if. -.(<op)e.'+';'-'  do.  break.  end.
  EP=:EP+1
  b=.script_term''
   if. op-:'+'  do. v=.v+b  else. v=.v-b  end.
  end.
 v
)
layout_all=:3 :0
 Veneers=:0$a:
  while. 1  do.
  build_components''
  place_segments''
  far=.far_calls''
  additions=.0$a:
   for_r. far  do. s=.section__r
  v=.symbol__r
  additions=.additions,<output__s;name__v  end.
  fresh=.(~.additions)-.Veneers
   if. 0=#fresh  do. FarCalls=:far
   break.  end.
  Veneers=:Veneers,fresh
  keys=.0$a:
   for_pair. Veneers  do. 'o n'=.>pair
  keys=.keys,<name__o,':',n  end.
  Veneers=:( /:keys){Veneers
  end.
  for_load. Loads  do.
  'a b'=.>load
  ga=.(SegmentNames i.<a){Segments
  gb=.(SegmentNames i.<b){Segments
  paddr__ga=:(base__gb+used__gb)align 4
  used__gb=:paddr__ga+filesz__ga-base__gb
  end.
  for_d. Defines  do.
  'name expression'=.>d
  ET=:script_tokens expression
  EP=:0
  r=.find_resolution name
  address__r=:script_expr''
  end.
)
check_symbols=:3 :0
 orphan=.0$a:
  for_s. Sections  do.  if. discard__s-:'orphan'  do. orphan=.orphan,<name__s  end.  end.
  for_n. /:~~.orphan  do. Diagnostics=:Diagnostics,<'warning: orphan section ',(>n),' discarded from ',(dec +/orphan=n),' object(s)' end.
  for_r. Resolutions  do.
  script=.kind__r-:'script'
   if. (script+#strong__r)>1  do.
   ds=.0$a:
    if. script  do. ds=.,<'*script*' end.
    for_s. strong__r  do. o=.owner__s
  ds=.ds,<name__o  end.
   Diagnostics=:Diagnostics,<'error: multiple definition of ',name__r,': ',' 'join ds
   end.
   if. #common__r  do.
    if. (<kind__r)e.'global';'script'  do. Diagnostics=:Diagnostics,<'warning: common symbol ',name__r,' overridden by ',definer__r
    elseif. kind__r-:'common'  do.
    pairs=.0$a:
     for_s. common__r  do. pairs=.pairs,<size__s,alignment__s  end.
     if. 1<#~.pairs  do. Diagnostics=:Diagnostics,<'warning: common symbol ',name__r,' merged to size ',(dec size__r),' align ',dec alignment__r  end.
    end.
   end.
  end.
 r=.find_resolution Entry
  if. r-:a:  do. bad=.1  else. bad=.(<kind__r)e.'undefined';'weakundef' end.
  if. bad  do. Diagnostics=:Diagnostics,<'error: entry symbol ',Entry,' is undefined' end.
  for_r. Resolutions  do.  if. kind__r-:'undefined'  do.
  refs=.0$a:
   for_o. Objects  do.
   found=.0
    for_re. relocs__o  do.
    s=.section__re
  v=.symbol__re
     if. live__s*.(-.binding__v-:'local')*.name__v-:name__r  do. found=.1 end.
    end.
    if. found  do. refs=.refs,<name__o  end.
   end.
   if. #refs  do. Diagnostics=:Diagnostics,<'error: undefined symbol ',name__r,' referenced by ',' 'join refs  end.
  end.  end.
)
check_segments=:3 :0
  for_g. Segments  do.  if. used__g>length__g  do. Diagnostics=:Diagnostics,<'error: segment ',name__g,' overflows its length by ',(dec used__g-length__g),' bytes' end.  end.
  for_i. i.#Segments  do.  for_j. (i+1)+i.(#Segments)-i+1  do.
  a=.i{Segments
  b=.j{Segments
   if. (memsz__a>0)*.(memsz__b>0)*.(base__a<base__b+memsz__b)*.base__b<base__a+memsz__a  do. Diagnostics=:Diagnostics,<'error: segments ',name__a,' and ',name__b,' overlap' end.
  end.  end.
)
apply_relocations=:3 :0
 RelocationLines=:0$a:
  counts=.7 4$0
 gp=.0
  if. (<'_gp')e.GlobalNames  do. r=.find_resolution '_gp'
  gp=.address__r  end.
  for_out. OutSections  do.  for_c. components__out  do.
   if. -.kind__c-:'input'  do.  continue.  end.
  s=.source__c
  o=.owner__s
  rs=.0$a:
   for_r. relocs__o  do.  if. s-:section__r  do. rs=.rs,r  end.  end.
   for_i. i.#rs  do.
   r=.i{rs
  v=.symbol__r
  typ=.type__r
   p=.address__s+offset__r
   loc=.name__o,' ',name__s,'+',dec offset__r
    if. rs unpaired i  do. Diagnostics=:Diagnostics,<'error: unpaired HI16 at ',loc,' against ',name__v  end.
   target=.symbol_value v
   line=.(8 hex p),' ',loc,' ',typ,' ',name__v,' ',dec addend__r
   status=.'ok'
    if. target=_1  do. status=.'undefined'
  line=.line,' - - -'
    else.
     if. r e.FarCalls  do.
      for_vc. components__out  do.  if. (kind__vc-:'veneer')*.name__vc-:name__v  do. target=.address__vc
  status=.'veneer'
   break.  end.  end.
     end.
    'val field good'=.reloc_field typ;target;addend__r;p;gp
     if. -.good  do. status=.'overflow'
  Diagnostics=:Diagnostics,<'error: relocation overflow at ',loc,': ',typ,' value ',(dec val),' against ',name__v  end.
    w=.width typ
    bytes__s=:(w little field)(offset__r+i.w)}bytes__s
    line=.line,' ',(8 hex target),' ',(dec val),' ',(2*w)hex field
    end.
   RelocationLines=:RelocationLines,<line,' ',status
   ti=.RelocTypes i.<typ
  si=.('ok';'veneer';'overflow';'undefined')i.<status
   counts=.(1+(<ti,si){counts)(<ti,si)}counts
   end.
  end.  end.
  for_i. i.7  do.
  row=.i{counts
  RelocationLines=:RelocationLines,<'summary ',(i{::RelocTypes),' total ',(dec +/row),' ok ',(dec 0{row),' veneer ',(dec 1{row),' overflow ',(dec 2{row),' undefined ',dec 3{row
  end.
)
create_images=:3 :0
  for_g. Segments  do.
  image__g=:filesz__g$fill__g
   for_out. outputs__g  do.  if. nobits name__out  do.  continue.  end.
    for_c. components__out  do.
     select. kind__c
     case. 'input'  do. s=.source__c
  data=.bytes__s
     case. 'merged'  do. data=.bytes__c
     case. 'veneer'  do. r=.find_resolution name__c
  v=.definition__r
  data=.4 240 31 229,4 little symbol_value v
     end.
    image__g=:data ((address__c-base__g)+i.#data)}image__g
    end.
   end.
  end.
  if. #Checksum  do.
  'name symbol'=.Checksum
  g=.(SegmentNames i.<name){Segments
  r=.find_resolution symbol
  v=.definition__r
  at=.(symbol_value v)-base__g
  image__g=:0 (at+i.4)}image__g
  padded=.image__g,((4| -#image__g)$0)
  total=.+/ ((_4[\padded) +/ . * 256^i.4)
  image__g=:(4 little 4294967296|-total)(at+i.4)}image__g
  end.
)
output_all=:3 :0
 entry=.0
  r=.find_resolution Entry
  if. -.r-:a:  do.  if. (<kind__r)e.'global';'weak'  do. entry=.symbol_value definition__r  elseif. kind__r-:'common'  do. entry=.address__r  end.  end.
 dump=.,<'entry ',(8 hex entry),' ',Entry
 map=.Extractions
  for_i. i.#ComdatNames  do. o=.i{ComdatKeepers
  map=.map,<'comdat ',(i{::ComdatNames),' ',name__o,' ',','join i{::ComdatDiscards  end.
 symbols=.0$a:
  symbolkeys=.0$a:
  for_g. Segments  do.
  header=.'segment ',name__g,' vaddr ',(8 hex base__g),' paddr ',(8 hex paddr__g),' filesz ',(dec filesz__g),' memsz ',dec memsz__g
  dump=.dump,<header
  map=.map,<header,' used ',(dec used__g),' length ',(dec length__g),' ',(dec <.100*used__g%length__g),'%'
   for_p. 16*i.>.filesz__g%16  do. dump=.dump,<(8 hex base__g+p),' ',' 'join (2&hex)&.><"0 (16<.filesz__g-p){.p}.image__g  end.
   for_out. outputs__g  do.
   map=.map,<'section ',name__out,' ',(8 hex address__out),' ',(dec size__out),' ',dec alignment__out
    for_c. components__out  do.
    prefix=.(8 hex address__c),' ',dec size__c
     select. kind__c
     case. 'input'  do. s=.source__c
  o=.owner__s
  line=.'input ',prefix,' ',(dec alignment__c),' ',name__o,' ',name__s
     case. 'merged'  do. line=.'merged ',prefix,' sections ',(dec #sources__c),' strings ',(dec count__c),' unique ',(dec unique__c),' saved ',dec saved__c
     case. 'common'  do. r=.source__c
  line=.'common ',prefix,' ',(dec alignment__c),' ',definer__r,' ',name__r
     case. 'veneer'  do.
     line=.'veneer ',prefix,' ',name__c
     nm=.'__veneer_',name__c
     symbols=.symbols,<'symbol ',(8 hex address__c),' ',nm,' veneer *linker*'
     symbolkeys=.symbolkeys,<(8 hex address__c),' ',nm
     end.
    map=.map,<line
    end.
   end.
  end.
  for_s. Sections  do.  if. #discard__s  do. o=.owner__s
  map=.map,<'discard ',name__o,' ',name__s,' ',(dec size__s),' ',discard__s  end.  end.
 xref=.0$a:
  for_r. Resolutions  do.
  kind=.kind__r
  stat=.'-'
  val=.0
  kept=.0
   select. kind
   case. 'script'  do. kept=.1
  val=.address__r
   case. 'common'  do. kept=.live__r
  val=.address__r
    if. -.kept  do. map=.map,<'discard ',definer__r,' COMMON(',name__r,') ',(dec size__r),' gc' end.
   case. 'global';'weak'  do. s=.definition__r
  t=.section__s
  kept=.live__t
   if. kept  do. val=.symbol_value s  end.
   end.
   if. -.(<kind)e.'undefined';'weakundef'  do. stat=.('discarded';'kept'){::~kept  end.
  xref=.xref,<name__r,' ',kind,' ',stat,' ',definer__r,' ',','join referrers__r
   if. kept  do. symbols=.symbols,<'symbol ',(8 hex val),' ',name__r,' ',kind,' ',definer__r
  symbolkeys=.symbolkeys,<(8 hex val),' ',name__r  end.
  end.
 map=.map,( /:symbolkeys){symbols
 ihex=.0$a:
  upper=.0
  addresses=.i.0
  for_g. Segments  do. addresses=.addresses,paddr__g  end.
  for_g. ( /:addresses){Segments  do.
  p=.0
   while. p<filesz__g  do.
   a=.paddr__g+p
  n=.16<.(filesz__g-p)<.65536-65536|a
   u=.<.a%65536
    if. u~:upper  do. upper=.u
  ihex=.ihex,<ihex_record 0;4;|.2 little u  end.
   ihex=.ihex,<ihex_record (65536|a);0;n{.p}.image__g
   p=.p+n
   end.
  end.
 ihex=.ihex,(<ihex_record 0;5;|.4 little entry),<':00000001FF'
 errors=.+/('error:'&-:@(6&{.))&>Diagnostics
 warnings=.#Diagnostics-errors
 Diagnostics=:Diagnostics,<'errors ',(dec errors),' warnings ',dec warnings
 'output/image.hex' write_lines dump
 'output/flash.ihex' write_lines ihex
 'output/link.map' write_lines map
 'output/xref.txt' write_lines xref
 'output/relocations.txt' write_lines RelocationLines
 'output/diagnostics.txt' write_lines Diagnostics
)
main=:3 :0
 Objects=:Sections=:Segments=:OutSections=:0$a:
 SegmentNames=:OutputNames=:Keeps=:Sorts=:Wraps=:ScriptNames=:Defines=:Loads=:Inputs=:0$a:
 ArchiveNames=:Archives=:ComdatNames=:ComdatKeepers=:ComdatDiscards=:Extractions=:Diagnostics=:0$a:
 Checksum=:0$a:
  for_line. readlines 'input/link.txt'  do.
  line=.>line
  w=.words line
   select. 0{::w
   case. 'entry'  do. Entry=:1{::w
   case. 'gc'  do. GC=:'on'-:1{::w
   case. 'segment'  do.
   g=.cocreate''
   name__g=:1{::w
  base__g=:num 2{::w
  length__g=:num 3{::w
  fill__g=:num 4{::w
   outputs__g=:0$a:
    for_n. 5}.w  do.
    out=.cocreate''
    name__out=:>n
  segment__out=:g
  outputs__g=:outputs__g,out
    OutSections=:OutSections,out
  OutputNames=:OutputNames,n
    end.
   Segments=:Segments,g
  SegmentNames=:SegmentNames,<name__g
   case. 'load'  do. Loads=:Loads,<1}.w
   case. 'keep'  do. Keeps=:Keeps,1{w
   case. 'sort'  do. Sorts=:Sorts,1{w
   case. 'wrap'  do. Wraps=:Wraps,1{w
   case. 'define'  do. ScriptNames=:ScriptNames,1{w
  eq=.line i.'='
  Defines=:Defines,<((1{::w);(eq+2)}.line)
   case. 'checksum'  do. Checksum=:1}.w
   case.  do. Inputs=:Inputs,<w
   end.
  end.
  for_input. Inputs  do.
  w=.>input
   select. 0{::w
   case. 'object'  do. load_object (1{::w)parse_object readlines 'input/',1{::w
   case. 'library'  do. scan_archive 1{::w
   case. 'group'  do.
    while. 1  do. count=.0
   for_n. 1}.w  do. count=.count+scan_archive >n  end.
   if. 0=count  do.  break.  end.  end.
   end.
  end.
 resolve_all''
 collect_live''
 check_symbols''
 layout_all''
 check_segments''
 apply_relocations''
 create_images''
 output_all''
 0
)
main''
