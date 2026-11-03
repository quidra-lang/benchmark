LF=:10{a.
dec=:3 : '(":y) rplc ''_'';''-'''
integers=:3 : '0".y rplc ''-'';''_'''
words=:3 : '<;._1 '' '',y'
readlines=:3 : '<;._2 (1!:1 <y)'
join=:4 :0
 if. 0=#y do. '' else. (#x)}.;(x&,)&.>y end.
)
numbers=:3 : ''' ''join dec&.><"0,y'
write_lines=:4 : '(;(,&LF)&.>y)1!:2<x'
read_ppm=:3 :0
 ls=.readlines y
 'w h'=.integers 1{::ls
 data=.integers >3}.ls
 (h,w,3)$,data
)
write_ppm=:4 :0
 'h w channels'=. $y
 lines=.'P3';((dec w),' ',dec h);'255'
 for_row. y do. lines=.lines,<numbers ,row end.
 x write_lines lines
)
read_hex=:3 : '16#. _2[\''0123456789abcdef''i.;readlines y'
write_hex=:4 :0
 lines=.0$a:
 for_p. 32*i.>. (#y)%32 do.
  bytes=.(32<.(#y)-p){.p}.y
  lines=.lines,<;('0123456789abcdef'{~16 16&#:)&.><"0 bytes
 end.
 x write_lines lines
)
read_configuration=:3 :0
 ls=.readlines 'input/params.txt'
 Qualities=:integers >}.words 0{::ls
 Sampling=:1{::words 1{::ls
 Restart=:integers 1{::words 2{::ls
 HuffmanMode=:1{::words 3{::ls
 TargetBytes=:integers 1{::words 4{::ls
 Generations=:integers 1{::words 5{::ls
 Truncations=:integers >}.words 6{::ls
 ls=.readlines 'input/tables.txt'
 C=:integers >1 2 3 4 5 6 7 8{ls
 Bases=:(integers >10 11 12 13 14 15 16 17{ls);integers >19 20 21 22 23 24 25 26{ls
 StandardTables=:8$a:
 for_i. i.4 do.
  p=.27+3*i
  'cls id'=.integers >}.words p{::ls
  t=.huffman_table (integers (p+1){::ls);integers (p+2){::ls
  StandardTables=:t ((4*cls)+id)}StandardTables
 end.
)
