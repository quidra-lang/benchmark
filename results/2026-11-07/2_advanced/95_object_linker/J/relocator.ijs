RelocTypes=:(<;._1 ' ','ABS32 REL32 ABS16 HI16 LO16 GPREL16 CALL24')
width=:3 : ' (4 4 2 2 2 2 3){~RelocTypes i.<y'
little=:4 : '256 | <. y % 256 ^ i.x'
reloc_field=:3 :0
 'typ s a p gp'=.y
 v=.s+a
  if. (<typ)e.'REL32';'CALL24'  do. v=.v-p  elseif. typ-:'GPREL16'  do. v=.v-gp  end.
  select. typ
  case. 'ABS32';'HI16'  do. good=.(v>:_2147483648)*.v<4294967296
  case. 'REL32'  do. good=.(v>:_2147483648)*.v<2147483648
  case. 'ABS16'  do. good=.(v>:_32768)*.v<65536
  case. 'GPREL16'  do. good=.(v>:_32768)*.v<32768
  case. 'CALL24'  do. good=.(v>:_33554432)*.v<33554432
  case. 'LO16'  do. good=.1
  end.
  if. typ-:'HI16'  do. f=.65536|<.((4294967296|v)+32768)%65536
  elseif. typ-:'CALL24'  do. f=.16777216|<.v%4
  else. f=.(256^width typ)|v  end.
 v;f;good
)
unpaired=:4 :0
 rs=.x
 i=.y
 r=.i{rs
  if. -.type__r-:'HI16'  do. 0  return.  end.
  if. i+1=#rs  do. 1  return.  end.
 t=.(i+1){rs
 -. (type__t-:'LO16')*.(symbol__r-:symbol__t)*.addend__r=addend__t
)
ihex_record=:3 :0
 'address typ data'=.y
 bytes=.(#data),(|.2 little address),typ,data
 bytes=.bytes,256|-+/bytes
 ':',toupper ;(2&hex)&.> <"0 bytes
)
