words =: 3 : '<;._1 '' '',y'
lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
num =: 3 : '0".''_''(I.y=''-'')}y'
upper =: 3 : 0
 a =. a.i.y
 a =. a-32*(a>:97)*.a<:122
 a.{~a
)
reverse_complement =: 3 : '''TGCAN''{~''ACGTN''i.|.y'
read_sequences =: 3 : 0
 RefNames =: Refs =: 0$a:
 Masked =: i.0
 for_l. lines 'reference.fasta' do.
  t =. >l
  if. '>'={.t do.
   RefNames =: RefNames,<0{::words }.t
   Refs =: Refs,<''
   Masked =: Masked,0
  else.
   i =. (#Refs)-1
   Refs =: (<(i{::Refs),upper t)i}Refs
   Masked =: ((i{Masked)++/t e.'acgt')i}Masked
  end.
 end.
 Offsets =: }:0,+/\1+#&>Refs
 RefLengths =: #&>Refs
 Reads =: 0$a:
 ls =. lines 'reads.fastq'
 for_i. 4*i.<.(#ls)%4 do. Reads =: Reads,< (}.i{::ls);((i+1){::ls);(i+3){::ls end.
 Keys =: Values =: 0$a:
 for_l. lines 'params.txt' do. fs =. words >l
 Keys =: Keys,{.fs
 Values =: Values,<num&>}.fs end.
 Text =: ('#'join Refs),'$'
 RevText =: (|.}:Text),'$'
 i.0 0
)
pv =: 3 : '(Keys i.<y){::Values'
pn =: 3 : '{.pv y'
reference_position =: 3 : 0
 for_r. i.#Refs do.
  if. (y>:r{Offsets)*.y<(r{Offsets)+r{RefLengths do. r,y-r{Offsets return. end.
 end.
 _1 _1
)
position_name =: 3 : 0
 'r pos' =. reference_position y
 if. r<0 do. '*' else. (r{::RefNames),':',str pos+1 end.
)
