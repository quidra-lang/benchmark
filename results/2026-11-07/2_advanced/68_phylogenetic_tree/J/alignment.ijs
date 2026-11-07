Alphabet =: 'ACGTRYSWKMBDHVN-'
BaseSets =: 1 2 4 8 5 10 6 9 12 3 14 13 11 7 15 15
words =: 3 : '<;._1 '' '',y'
lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
num =: 3 : '0".''_''(I.y=''-'')}y'
upper =: 3 : 0
 a =. a.i.y
 a =. a-32*(a>:97)*.a<:122
 a.{~a
)
read_alignment =: 3 : 0
 ParamKeys =: ParamValues =: 0$a:
 for_l. lines 'params.txt' do.
  f =. words >l
  ParamKeys =: ParamKeys,{.f
  ParamValues =: ParamValues,<}.f
 end.
 RecordNames =: RecordSequences =: 0$a:
 RecordLines =: i.0
 input =. lines 'alignment.fasta'
 for_i. i.#input do.
  text =. i{::input
  if. '>'={.text do.
   RecordNames =: RecordNames,<0{::words }.text
   RecordSequences =: RecordSequences,<''
   RecordLines =: RecordLines,i+1
  else.
   j =. (#RecordSequences)-1
   RecordSequences =: (<(j{::RecordSequences),upper text)j}RecordSequences
  end.
 end.
 L =: #0{::RecordSequences
 Names =: Sequences =: Rejects =: 0$a:
 seen =. 0$a:
 for_i. i.#RecordNames do.
  name =. i{::RecordNames
  seq =. i{::RecordSequences
  reason =. ''
  invalid =. I.-.seq e.Alphabet
  missing =. +/seq e.'N-'
  if. (<name)e.seen do. reason =. 'duplicate name'
  elseif. #invalid do. j =. {.invalid
  reason =. emit 'invalid character';(,j{seq);'at column';j+1
  elseif. (#seq)~:L do. reason =. emit 'length mismatch';#seq
  elseif. (100*missing)>(pn 'max_missing_percent')*L do. reason =. emit 'too many missing';missing end.
  seen =. seen,<name
  if. #reason do. Rejects =: Rejects,<emit 'REJECT line';(i{RecordLines);name;reason
  else. Names =: Names,<name
  Sequences =: Sequences,<seq end.
 end.
 N =: #Names
 Alignment =: >Sequences
 Sets =: BaseSets{~Alphabet i.Alignment
 Outgroup =: Names i.0{pv 'outgroup'
 Ingroup =: (i.N)-.Outgroup
 Model =: 0{::pv 'model'
 Models =: 'P';'JC';'K2P'
 MainModel =: Models i.<Model
 ExhaustiveTaxa =: Outgroup,/:~(Names i.pv 'exhaustive_taxa')-.Outgroup
 Replicates =: pn 'replicates'
 Seed =: pn 'seed'
 Hypotheses =: words&.>lines 'clades.txt'
 Patterns =: ~.<"1|:Alignment
 i.0 0
)
pv =: 3 : '(ParamKeys i.<y){::ParamValues'
pn =: 3 : 'num 0{::pv y'
column_classes =: 3 : 0
 counts =. +/"1 'ACGT'=/y
 kinds =. +/counts>0
 (kinds=1),(kinds>:2),(2<:+/counts>:2),('-'e.y),kinds=0
)
