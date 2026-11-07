bit_writer=:3 :0
 Written=:PendingBits=:i.0
 PaddingBits=:StuffedBytes=:0
)
write_bits=:4 :0
 if. x=0 do. return. end.
 PendingBits=:PendingBits,(x$2)#:y
 while. (#PendingBits)>:8 do.
  byte=.2#.8{.PendingBits
  PendingBits=:8}.PendingBits
  Written=:Written,byte
  if. byte=255 do. Written=:Written,0 [ StuffedBytes=:StuffedBytes+1 end.
 end.
)
pad_bits=:3 :0
 n=.8| -#PendingBits
 PaddingBits=:PaddingBits+n
 n write_bits (2^n)-1
)
append_marker=:3 : 'Written=:Written,255,y'
read_error=:3 :0
 DecodeError=:y
 13!:8]3
)
read_bits=:3 :0
 result=.0
 for_i. i.y do.
  if. 0=#ReadBuffer do.
   b=.ReadPosition{ReadBytes
   if. b=255 do.
    if. 0~:(ReadPosition+1){ReadBytes do. read_error 'marker' end.
    ReadPosition=:ReadPosition+2
   else. ReadPosition=:ReadPosition+1 end.
   ReadBuffer=:8$2
   ReadBuffer=:ReadBuffer#:b
  end.
  result=.(2*result)+{.ReadBuffer
  ReadBuffer=:}.ReadBuffer
 end.
 result
)
read_symbol=:3 :0
 t=.y
 code=.0
 for_l. 1+i.16 do.
  code=.(2*code)+read_bits 1
  candidates=.values__t#~l=values__t{lengths__t
  for_symbol. candidates do.
   if. code=symbol{codes__t do. symbol return. end.
  end.
 end.
 read_error 'code'
)
resynchronize=:3 :0
 p=.y
 while. p+1<#ReadBytes do.
  if. 255=p{ReadBytes do.
   marker=.(p+1){ReadBytes
   if. (marker=217)+.(marker>:208)*.marker<:215 do. p return. end.
  end.
  p=.p+1
 end.
 p
)
