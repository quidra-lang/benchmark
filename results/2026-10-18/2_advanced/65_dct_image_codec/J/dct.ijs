zigzag_order=:3 :0
 result=.i.0
 for_sum. i.15 do.
  us=.(0>.sum-7)+i.1+(7<.sum)-(0>.sum-7)
  if. 0=2|sum do. us=.|.us end.
  for_u. us do. result=.result,(8*u)+sum-u end.
 end.
 result
)
Zig=:zigzag_order''
round_shift=:4 : '<.(y+2^x-1)%2^x'
dct_forward=:3 :0
 e=.11 round_shift C +/ . * y-128
 15 round_shift e +/ . * |:C
)
dct_inverse=:3 :0
 s=.11 round_shift (|:C) +/ . * y
 clamp 128+15 round_shift s +/ . * C
)
quantization_tables=:3 :0
 q=.y
 if. q<50 do. scale=.<.5000%q else. scale=.200-2*q end.
 result=.0$a:
 for_base. Bases do.
  table=.1>.255<.<.(50+scale*,>base)%100
  result=.result,<Zig{table
 end.
 result
)
quantize=:4 :0
 values=.Zig{,y
 magnitude=.<.((|values)+<.x%2)%x
 (*values)*magnitude
)
dequantize=:4 : '8 8$(x*y)Zig}64$0'
block_pixels=:4 :0
 'bx by'=.x
 ((8*bx)+i.8){"1 ((8*by)+i.8){y
)
put_block=:4 :0
 'plane bx by'=.x
 for_j. i.8 do.
  for_i. i.8 do.
   plane=.((<j,i){y)(<((8*by)+j),((8*bx)+i))}plane
  end.
 end.
 plane
)
