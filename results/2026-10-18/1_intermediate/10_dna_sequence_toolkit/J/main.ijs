NB. Exact integer algorithms, indexed registry, and explicit validation phases.
LF=:10{a.
SYMBOLS=:'ACGTRYWSKMBDHVN'
PARTNERS=:'TGCAYRWSMKVHDBN'
SETS=:,&.>'A';'C';'G';'T';'AG';'CT';'AT';'CG';'GT';'AC';'CGT';'AGT';'ACT';'ACG';'ACGT'
CODE=:'FFLLSSSSYY**CC*WLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG'
ENZYMES=.;:'EcoRI BamHI HindIII PstI SmaI KpnI XbaI NotI EcoRV HaeIII AluI TaqI Sau3AI HincII AvaI'
MOTIFS=.;:'GAATTC GGATCC AAGCTT CTGCAG CCCGGG GGTACC TCTAGA GCGGCCGC GATATC GGCC AGCT TCGA GATC GTYRAC CYCGRG'
OFFSETS=:1 1 1 5 3 5 1 2 3 2 2 1 0 3 1
split=:4:0
  <;._1 x,y
)
join=:4:0
  if. 0=#y do. '' return. end.
  (#x)}.;(<x),&.>y
)
text_equal=:4:0
  (,x)-:,y
)
number=:3:0
  ,'0' 8!:2 y
)
floor_ratio=:4:0
  <.(x:x)%x:y
)
number_value=:3:0
  negative=.'-'={.y
  digits=.y
  if. negative do. digits=.}.y end.
  if. (0=#digits)+.((#digits)>6)+.-.*./digits e.'0123456789' do. 1000000000 return. end.
  value=.0".digits
  if. negative do. -value else. value end.
)
fixed_digits=:4:0
  text=.number y
  ((0>.x-#text)#'0'),text
)
hundredths=:3:0
  (number y floor_ratio 100),'.',2 fixed_digits 100|y
)
percentage=:4:0
  hundredths (10000*x)floor_ratio y
)
milli=:3:0
  (number y floor_ratio 1000),'.',3 fixed_digits 1000|y
)
tenths=:3:0
  (number y floor_ratio 10),'.',number 10|y
)
numbers=:3:0
  if. 0=#y do. 'none' return. end.
  ' 'join number&.>y
)
complement=:3:0
  (SYMBOLS i.y){PARTNERS
)
reverse_complement=:3:0
  |.complement y
)
transition=:4:0
  if. x text_equal y do. 0 return. end.
  ((x e.'AG')*.y e.'AG')+.((x e.'CT')*.y e.'CT')
)
symbol_bases=:3:0
  (SYMBOLS i.{.,y){::SETS
)
occurrences=:4:0
  sequence=.x
  motif=.y
  result=.i.0
  for_start. i.0>.1+(#sequence)-#motif do.
    matches=.1
    for_k. i.#motif do.
      if. -.((start+k){sequence)e.symbol_bases k{motif do. matches=.0 break. end.
    end.
    if. matches do. result=.result,start+1 end.
  end.
  result
)
amino_acid=:3:0
  codes=.'TCAG'i.y
  index=.(16*0{codes)+(4*1{codes)+2{codes
  index{CODE
)
codon_list=:4:0
  strand=.x
  if. y<0 do. strand=.reverse_complement strand end.
  strand=.((|y)-1)}.strand
  count=.(#strand)floor_ratio 3
  <"1(count,3)$(3*count){.strand
)
translate=:3:0
  ;amino_acid&.>y
)
composition=:3:0
  +/"1 'ACGT'=/y
)
gc_count=:3:0
  counts=.composition y
  (1{counts)+2{counts
)
melting_temperature=:3:0
  count=.#y
  gc=.gc_count y
  if. count<14 do. 10*((2*count-gc)+4*gc)
  else. ((649*count)+(410*gc)-6724)floor_ratio count end.
)
sequence_mass=:3:0
  masses=.331222 307197 347221 322208
  (+/('ACGT'i.y){masses)-18015*(#y)-1
)
repeat_count=:4:0
  'start width'=.x
  count=.1
  unit=.width{.start}.y
  while. (start+(count+1)*width)<:#y do.
    if. -.unit text_equal width{.(start+count*width)}.y do. break. end.
    count=.count+1
  end.
  count
)
primitive=:3:0
  width=.#y
  for_divisor. 1+i.width-1 do.
    if. 0~:divisor|width do. continue. end.
    if. y text_equal width$divisor{.y do. 0 return. end.
  end.
  1
)
sequence_id=:3:0
  index=.(NR{.REGNAMES)i.<,y
  if. index=NR do. _1 else. index end.
)
valid_name=:3:0
  if. (0=#y)+.(#y)>10 do. 0 return. end.
  if. -.({.y)e.'abcdefghijklmnopqrstuvwxyz' do. 0 return. end.
  *./(}.y)e.'abcdefghijklmnopqrstuvwxyz0123456789'
)
registration=:4:0
  name=.x
  sequence=.y
  if. (#sequence)>500 do. 'ERROR too long' return. end.
  index=.sequence_id name
  replacing=.index>:0
  if. index<0 do.
    index=.NR
    NR=:NR+1
  end.
  REGNAMES=:(<,name)index}REGNAMES
  REGSEQ=:(<sequence)index}REGSEQ
  if. replacing do. prefix=.'replaced ' else. prefix=.'stored ' end.
  prefix,name,' ',(number #sequence),' nt'
)
initialize=:3:0
  definitions=.'|'split 'SEQ 2 2 NS|SLICE 4 4 RIIN|JOIN 3 9 NR|MUTATE 3 3 RIB|DEL 1 1 R|LIST 0 0 -|REVCOMP 1 1 R|COMPLEMENT 1 1 R|REVERSE 1 1 R|TRANSCRIBE 1 1 R|TRANSLATE 2 2 RI|CODONS 2 2 RI|PROTEIN 2 2 RI|ORFS 2 2 RI|GC 1 1 R|GCWINDOW 3 3 RII|SKEW 1 1 R|KMERS 3 3 RII|FIND 2 2 RM|RESTRICT 2 7 RE|PALINDROMES 3 3 RII|REPEATS 4 4 RIII|HAMMING 2 2 RR|ALIGN 6 6 RROIII|CONSENSUS 2 10 R|TM 1 1 R|MASS 1 1 R|PRIMER 1 1 R|FOLD 2 2 RI|ASSEMBLE 4 10 NIR|PACK 1 1 R|UNPACK 3 3 NIH'
  COMMANDS=:0$a:
  MINS=:i.0
  MAXS=:i.0
  KINDS=:0$a:
  for_definition. definitions do.
    parts=.' 'split >definition
    COMMANDS=:COMMANDS,0{parts
    MINS=:MINS,0".1{::parts
    MAXS=:MAXS,0".2{::parts
    KINDS=:KINDS,3{parts
  end.
  REGNAMES=:400$<''
  REGSEQ=:400$<''
  NR=:0
)
number_range=:3:0
  'action argument length'=.y
  if. (<action)e.;:'SLICE MUTATE' do. 1,length return. end.
  if. (<action)e.;:'TRANSLATE CODONS PROTEIN' do. _3 3 return. end.
  if. 'ORFS'text_equal action do. 1 200 return. end.
  if. (<action)e.;:'GCWINDOW UNPACK' do. 1 500 return. end.
  if. 'KMERS'text_equal action do. if. argument=1 do. 1 12 else. 1 100 end. return. end.
  if. 'PALINDROMES'text_equal action do. 2 20 return. end.
  if. 'REPEATS'text_equal action do. if. argument<3 do. 1 6 else. 2 50 end. return. end.
  if. 'ALIGN'text_equal action do.
    if. argument=3 do. 1 20 elseif. argument=4 do. _20 0 else. _20 _1 end.
    return.
  end.
  if. 'FOLD'text_equal action do. 0 10 else. 1 100 end.
)
validation=:4:0
  cmd=.x
  args=.y
  action=.cmd{::COMMANDS
  kinds=.cmd{::KINDS
  length=.0
  unpacklength=.0
  enzymes=.0$a:
  for_k. i.#args do.
    text=.k{::args
    kind=.(k<.(#kinds)-1){kinds
    select. kind
    case. 'R' do.
      index=.sequence_id text
      if. index<0 do. 'unknown sequence ',text return. end.
      if. k=0 do. length=.#index{::REGSEQ end.
    case. 'N' do. if. -.valid_name text do. 'invalid name ',text return. end.
    case. 'I' do.
      value=.number_value text
      limits=.number_range (<action),(<k),<length
      invalid=.(value<0{limits)+.value>1{limits
      if. (<action)e.;:'TRANSLATE CODONS PROTEIN' do. invalid=.invalid+.value=0 end.
      if. invalid do. 'invalid number ',text return. end.
      if. 'UNPACK'text_equal action do. unpacklength=.value end.
    case. 'S' do.
      for_position. i.#text do.
        if. -.(position{text)e.'ACGT' do. 'invalid base ',(position{text),' at ',number position+1 return. end.
      end.
    case. 'B' do.
      if. (1~:#text)+.-.*./text e.'ACGT' do. 'invalid base ',text return. end.
    case. 'M' do.
      if. (0=#text)+.((#text)>30)+.-.*./text e.SYMBOLS do. 'invalid motif ',text return. end.
    case. 'E' do.
      if. -. (<text)e.ENZYMES do. 'unknown enzyme ',text return. end.
      if. (<text)e.enzymes do. 'duplicate enzyme ',text return. end.
      enzymes=.enzymes,<text
    case. 'O' do. if. -.(<text)e.'GLOBAL';'LOCAL' do. 'invalid mode ',text return. end.
    case. 'H' do.
      if. ((#text)~:2*(unpacklength+3)floor_ratio 4)+.-.*./text e.'0123456789ABCDEF' do. 'invalid hex' return. end.
    end.
  end.
  ''
)
frequencies=:3:0
  keys=./:~~.y
  counts=.+/"1 keys=/y
  order=.\:counts
  (<order{keys),<order{counts
)
align_sequences=:3:0
  'a b localalignment matchscore mismatch gap'=.y
  m=.#a
  n=.#b
  h=.((m+1),(n+1))$0
  if. -.localalignment do.
    for_i. i.m+1 do. h=.(i*gap)(<i,0)}h end.
    for_j. i.n+1 do. h=.(j*gap)(<0,j)}h end.
  end.
  best=.0
  enda=.0
  endb=.0
  for_i. 1+i.m do.
    for_j. 1+i.n do.
      sigma=.mismatch
      if. ((i-1){a)=(j-1){b do. sigma=.matchscore end.
      diagonal=.sigma+(<(i-1),(j-1)){h
      value=.diagonal>.gap+((<(i-1),j){h)>.(<i,(j-1)){h
      if. localalignment do. value=.0>.value end.
      h=.value(<i,j)}h
      if. value>best do.
        best=.value
        enda=.i
        endb=.j
      end.
    end.
  end.
  if. -.localalignment do.
    enda=.m
    endb=.n
    best=.(<m,n){h
  elseif. best=0 do. <'score 0' return. end.
  i=.enda
  j=.endb
  rowa=.''
  rowb=.''
  middle=.''
  identity=.0
  gaps=.0
  while. (i>0)+.j>0 do.
    current=.(<i,j){h
    if. localalignment*.current=0 do. break. end.
    diagonal=.0
    if. (i>0)*.j>0 do.
      sigma=.mismatch
      if. ((i-1){a)=(j-1){b do. sigma=.matchscore end.
      diagonal=.current=sigma+(<(i-1),(j-1)){h
    end.
    up=.0
    if. i>0 do. up=.current=gap+(<(i-1),j){h end.
    if. diagonal do.
      x=.(i-1){a
      z=.(j-1){b
      i=.i-1
      j=.j-1
    elseif. up do.
      x=.(i-1){a
      z=.'-'
      i=.i-1
    else.
      x=.'-'
      z=.(j-1){b
      j=.j-1
    end.
    rowa=.rowa,x
    rowb=.rowb,z
    if. (x='-')+.z='-' do.
      middle=.middle,'-'
      gaps=.gaps+1
    elseif. x=z do.
      middle=.middle,'|'
      identity=.identity+1
    else. middle=.middle,'*' end.
  end.
  header=.'score ',(number best),' a ',(number i+1),'-',(number enda),' b ',(number j+1),'-',(number endb),' identity ',(number identity),'/',(number #rowa),' gaps ',number gaps
  (<header),(<|.rowa),(<|.middle),<|.rowb
)
fold_value=:4:0
  'first last'=.x
  if. first>last do. 0 else. (<first,last){y end.
)
rna_pair=:4:0
  ((complement x)text_equal y)+.((x='G')*.y='T')+.((x='T')*.y='G')
)
fold_sequence=:4:0
  sequence=.x
  minimumloop=.y
  n=.#sequence
  table=.(n,n)$0
  for_width. 1+i.n do.
    for_first. i.1+n-width do.
      last=.first+width-1
      best=.(first,last-1)fold_value table
      for_k. first+i.0>.(last-minimumloop)-first do.
        if. (k{sequence)rna_pair last{sequence do.
          candidate=.(first,k-1)fold_value table
          candidate=.candidate+1+((k+1),(last-1))fold_value table
          best=.best>.candidate
        end.
      end.
      table=.best(<first,last)}table
    end.
  end.
  starts=.(1+2*n)#0
  ends=.(1+2*n)#0
  ends=.(n-1)0}ends
  pending=.1
  symbols=.n#'.'
  while. pending>0 do.
    pending=.pending-1
    first=.pending{starts
    last=.pending{ends
    value=.(first,last)fold_value table
    if. value=0 do. continue. end.
    if. value=(first,last-1)fold_value table do.
      starts=.first pending}starts
      ends=.(last-1)pending}ends
      pending=.pending+1
    else.
      for_k. first+i.0>.(last-minimumloop)-first do.
        if. (k{sequence)rna_pair last{sequence do.
          candidate=.(first,k-1)fold_value table
          candidate=.candidate+1+((k+1),(last-1))fold_value table
          if. candidate=value do.
            symbols=.'('k}symbols
            symbols=.')'last}symbols
            starts=.first pending}starts
            ends=.(k-1)pending}ends
            starts=.(k+1)(pending+1)}starts
            ends=.(last-1)(pending+1)}ends
            pending=.pending+2
            break.
          end.
        end.
      end.
    end.
  end.
  (<symbols),<'pairs ',number (<0,(n-1)){table
)
suffix_overlap=:4:0
  limit=.(#x)<.#y
  limit=.limit-1
  if. limit<:0 do. 0 return. end.
  text=.(limit{.y),'#',(-limit){.x
  prefix=.(#text)#0
  for_k. 1+i.(#text)-1 do.
    matched=.(k-1){prefix
    while. matched>0 do.
      if. (k{text)=matched{text do. break. end.
      matched=.(matched-1){prefix
    end.
    if. (k{text)=matched{text do. matched=.matched+1 end.
    prefix=.matched k}prefix
  end.
  {:prefix
)
assemble=:3:0
  'name minimumoverlap inputs'=.y
  unique=.~.inputs
  fragments=.0$a:
  for_k. i.#unique do.
    contained=.0
    for_j. i.#unique do.
      if. j~:k do. if. 1 e.(k{::unique)E.j{::unique do. contained=.1 end. end.
    end.
    if. -.contained do. fragments=.fragments,k{unique end.
  end.
  while. (#fragments)>1 do.
    best=.0
    first=.0
    second=.1
    for_k. i.#fragments do.
      for_j. i.#fragments do.
        if. k=j do. continue. end.
        overlap=.(k{::fragments)suffix_overlap j{::fragments
        if. overlap>best do.
          best=.overlap
          first=.k
          second=.j
        end.
      end.
    end.
    if. best<minimumoverlap do. break. end.
    joined=.(first{::fragments),best}.second{::fragments
    remaining=.0$a:
    for_k. i.#fragments do.
      if. k=first do. remaining=.remaining,<joined
      elseif. k~:second do.
        if. -.1 e.(k{::fragments)E.joined do. remaining=.remaining,k{fragments end.
      end.
    end.
    fragments=.remaining
  end.
  lengths=.#&>fragments
  longest=.lengths i.>./lengths
  if. (longest{lengths)>500 do. <'ERROR too long' return. end.
  output=.0$a:
  output=.output,<'contigs ',number #fragments
  for_fragment. fragments do.
    text=.>fragment
    output=.output,<(number #text),' ',text
  end.
  output,<name registration longest{::fragments
)
execute=:3:0
  words=.' 'split y
  action=.0{::words
  cmd=.COMMANDS i.<action
  if. cmd=#COMMANDS do. <'ERROR unknown command ',action return. end.
  args=.}.words
  count=.#args
  if. (count<cmd{MINS)+.count>cmd{MAXS do. <'ERROR wrong argument count' return. end.
  reason=.cmd validation args
  if. #reason do. <'ERROR ',reason return. end.
  if. 'LIST'text_equal action do.
    names=.(NR{.REGNAMES)#~0<#&>NR{.REGNAMES
    names=./:~names
    output=.0$a:
    for_name. names do.
      name=.>name
      output=.output,<name,' ',(number #(sequence_id name){::REGSEQ),' nt'
    end.
    if. 0=#output do. <'no sequences' else. output end.
    return.
  end.
  if. 'SEQ'text_equal action do. <(0{::args)registration 1{::args return. end.
  if. 'UNPACK'text_equal action do.
    length=.number_value 1{::args
    encoded=.2{::args
    sequence=.''
    for_k. i.(#encoded)floor_ratio 2 do.
      byte=.(16*'0123456789ABCDEF'i.(2*k){encoded)+'0123456789ABCDEF'i.(1+2*k){encoded
      codes=.(byte floor_ratio 64),(4|byte floor_ratio 16),(4|byte floor_ratio 4),4|byte
      for_code. codes do.
        if. ((#sequence)>:length)*.code~:0 do. <'ERROR invalid padding' return. end.
        sequence=.sequence,code{'ACGT'
      end.
    end.
    <(0{::args)registration length{.sequence
    return.
  end.
  if. (<action)e.;:'JOIN ASSEMBLE' do.
    first=.1
    if. 'ASSEMBLE'text_equal action do. first=.2 end.
    fragments=.0$a:
    for_k. first+i.count-first do. fragments=.fragments,<(sequence_id k{::args){::REGSEQ end.
    if. 'JOIN'text_equal action do. <(0{::args)registration ''join fragments
    else. assemble (<0{::args),(<number_value 1{::args),<fragments end.
    return.
  end.
  index=.sequence_id 0{::args
  sequence=.index{::REGSEQ
  length=.#sequence
  select. action
  case. 'DEL' do.
    REGNAMES=:(<'')index}REGNAMES
    REGSEQ=:(<'')index}REGSEQ
    <'deleted ',0{::args return.
  case. 'SLICE' do.
    first=.(number_value 1{::args)-1
    last=.(number_value 2{::args)-1
    if. first<:last do. part=.(1+last-first){.first}.sequence
    else. part=.reverse_complement (1+first-last){.last}.sequence end.
    <(3{::args)registration part return.
  case. 'MUTATE' do.
    position=.(number_value 1{::args)-1
    base=.2{::args
    original=.position{sequence
    if. original text_equal base do. <'ERROR no change' return. end.
    REGSEQ=:(<((position{.sequence),base,(position+1)}.sequence))index}REGSEQ
    if. original transition {.base do. kind=.'transition' else. kind=.'transversion' end.
    <(0{::args),' ',original,(number position+1),base,' ',kind return.
  case. 'REVCOMP' do. <reverse_complement sequence return.
  case. 'COMPLEMENT' do. <complement sequence return.
  case. 'REVERSE' do. <|.sequence return.
  case. 'TRANSCRIBE' do. <'U'(I.sequence='T')}sequence return.
  end.
  if. (<action)e.;:'TRANSLATE CODONS PROTEIN' do.
    codons=.sequence codon_list number_value 1{::args
    protein=.translate codons
    if. 'TRANSLATE'text_equal action do.
      if. 0=#protein do. <'none' else. <protein end.
      return.
    end.
    if. 'CODONS'text_equal action do.
      'keys counts'=.frequencies codons
      output=.0$a:
      for_k. i.#keys do. key=.k{::keys
        output=.output,<key,' ',(amino_acid key),' ',number k{counts
      end.
      if. 0=#output do. <'none' else. output end.
      return.
    end.
    protein=.(protein i.'*'){.protein
    if. 0=#protein do. <'ERROR empty protein' return. end.
    alphabet=.'ACDEFGHIKLMNPQRSTVWY'
    masses=.71079 103139 115089 129116 147177 57052 137141 113160 128174 113160 131193 114104 97117 128131 156188 87078 101105 99133 186213 163176
    mass=.18015++/(alphabet i.protein){masses
    charge=.(+/protein e.'KR')-+/protein e.'DE'
    letters=.<"0 protein
    'keys counts'=.frequencies letters
    parts=.0$a:
    for_k. i.#keys do. parts=.parts,<(k{::keys),'=',number k{counts end.
    sign=.''
    if. charge>0 do. sign=.'+' end.
    (<protein),(<'length ',(number #protein),' mass ',(milli mass),' charge ',sign,number charge),<' 'join parts
    return.
  end.
  select. action
  case. 'ORFS' do.
    threshold=.number_value 1{::args
    starts=.i.0
    lines=.0$a:
    for_frame. 1 2 3 _1 _2 _3 do.
      codons=.sequence codon_list frame
      start=._1
      for_k. i.#codons do.
        codon=.k{::codons
        if. (start<0)*.'ATG'text_equal codon do. start=.k
        elseif. (start>:0)*.'*'=amino_acid codon do.
          if. (k-start)>:threshold do.
            left=.(|frame)+3*start
            right=.(|frame)+2+3*k
            if. frame<0 do.
              converted=.length+1-right
              right=.length+1-left
              left=.converted
            end.
            protein=.translate (k-start){.start}.codons
            sign=.''
            if. frame>0 do. sign=.'+' end.
            starts=.starts,left
            lines=.lines,<sign,(number frame),' ',(number left),' ',(number right),' ',(number k-start),' ',protein
          end.
          start=._1
        end.
      end.
    end.
    if. 0=#lines do. <'none' else. (/:starts){lines end.
  case. 'GC' do.
    counts=.composition sequence
    <'A=',(number 0{counts),' C=',(number 1{counts),' G=',(number 2{counts),' T=',(number 3{counts),' GC=',(((1{counts)+2{counts)percentage length),'%'
  case. 'GCWINDOW' do.
    width=.number_value 1{::args
    step=.number_value 2{::args
    if. width>length do. <'ERROR window too large' return. end.
    output=.0$a:
    position=.0
    while. (position+width)<:length do.
      gc=.gc_count width{.position}.sequence
      output=.output,<(number position+1),'-',(number position+width),' ',(gc percentage width),'%'
      position=.position+step
    end.
    output
  case. 'SKEW' do.
    values=.0,+/\(sequence='G')-sequence='C'
    low=.<./values
    high=.>./values
    (<'min ',(number low),' at ',numbers I.values=low),<'max ',(number high),' at ',numbers I.values=high
  case. 'KMERS' do.
    width=.number_value 1{::args
    limit=.number_value 2{::args
    if. width>length do. <'ERROR k too large' return. end.
    windows=.0$a:
    for_k. i.1+length-width do. windows=.windows,<width{.k}.sequence end.
    'keys counts'=.frequencies windows
    output=.0$a:
    output=.output,<(number #windows),' windows ',(number #keys),' distinct'
    for_k. i.limit<.#keys do. output=.output,<(k{::keys),' ',number k{counts end.
    output
  case. 'FIND' do.
    motif=.1{::args
    (<'forward ',numbers sequence occurrences motif),<'reverse ',numbers sequence occurrences reverse_complement motif
  case. 'RESTRICT' do.
    cuts=.(length+1)#0
    output=.0$a:
    for_k. 1+i.count-1 do.
      enzyme=.ENZYMES i.k{args
      points=.(sequence occurrences enzyme{::MOTIFS)+(enzyme{OFFSETS)-1
      points=.points#~(points>:1)*.points<length
      cuts=.1 points}cuts
      output=.output,<(k{::args),' ',numbers points
    end.
    cuts=.1 length}cuts
    first=.1
    fragments=.0$a:
    sizes=.i.0
    for_cut. I.cuts do.
      fragments=.fragments,<(number first),'-',number cut
      sizes=.sizes,1+cut-first
      first=.cut+1
    end.
    output,(<'fragments ',' 'join fragments),<'sizes ',numbers \:~sizes
  case. 'PALINDROMES';'REPEATS' do.
    firstwidth=.number_value 1{::args
    lastwidth=.number_value 2{::args
    if. firstwidth>lastwidth do. <'ERROR invalid range' return. end.
    output=.0$a:
    if. 'PALINDROMES'text_equal action do.
      for_position. i.length do.
        for_width. firstwidth+i.1+lastwidth-firstwidth do.
          if. (position+width)<:length do.
            part=.width{.position}.sequence
            if. part text_equal reverse_complement part do. output=.output,<(number position+1),' ',(number width),' ',part end.
          end.
        end.
      end.
    else.
      keys=.0 2$0
      for_width. firstwidth+i.1+lastwidth-firstwidth do.
        position=.0
        while. (position+width)<:length do.
          unit=.width{.position}.sequence
          repeats=.(position,width)repeat_count sequence
          found=.(primitive unit)*.repeats>:number_value 3{::args
          if. found do.
            keys=.keys,position,width
            output=.output,<(number position+1),'-',(number position+repeats*width),' ',unit,'x',number repeats
            position=.position+repeats*width
          else. position=.position+1 end.
        end.
      end.
      output=.( /:keys){output
    end.
    if. 0=#output do. <'none' else. output end.
  case. 'HAMMING' do.
    other=.(sequence_id 1{::args){::REGSEQ
    if. (#other)~:length do. <'ERROR length mismatch' return. end.
    transitions=.0
    transversions=.0
    for_k. i.length do.
      if. (k{sequence)~:k{other do.
        if. (k{sequence)transition k{other do. transitions=.transitions+1 else. transversions=.transversions+1 end.
      end.
    end.
    <'distance ',(number transitions+transversions),' transitions ',(number transitions),' transversions ',number transversions
  case. 'ALIGN' do.
    other=.(sequence_id 1{::args){::REGSEQ
    localalignment=.'LOCAL'text_equal 2{::args
    align_sequences (<sequence),(<other),(<localalignment),(<number_value 3{::args),(<number_value 4{::args),<number_value 5{::args
  case. 'CONSENSUS' do.
    for_name. args do.
      if. length~:#(sequence_id >name){::REGSEQ do. <'ERROR length mismatch' return. end.
    end.
    profile=.(4,length)$0
    for_name. args do.
      other=.(sequence_id >name){::REGSEQ
      for_k. i.length do.
        base=.'ACGT'i.k{other
        profile=.(1+(<base,k){profile)(<base,k)}profile
      end.
    end.
    consensus=.''
    iupac=.''
    for_k. i.length do.
      counts=.k{"1 profile
      best=.>./counts
      tied=.'ACGT'#~counts=best
      consensus=.consensus,{.tied
      index=.SETS i.<tied
      iupac=.iupac,index{SYMBOLS
    end.
    output=.0$a:
    for_base. i.4 do. output=.output,<(base{'ACGT'),' ',numbers base{profile end.
    output,(<'consensus ',consensus),<'iupac ',iupac
  case. 'TM' do.
    if. length<14 do. method=.'wallace' else. method=.'gc' end.
    <'Tm ',(tenths melting_temperature sequence),' ',method
  case. 'MASS' do.
    mass=.sequence_mass sequence
    <'ss ',(milli mass),' ds ',milli mass+sequence_mass reverse_complement sequence
  case. 'FOLD' do.
    if. length>100 do. <'ERROR too long' return. end.
    sequence fold_sequence number_value 1{::args
  case. 'PACK' do.
    groups=.(length+3)floor_ratio 4
    codes=.(4*groups){.'ACGT'i.sequence
    bytes=.4#."1(groups,4)$codes
    encoded=.(,16 16#:bytes){'0123456789ABCDEF'
    <(number length),' ',encoded
  case. 'PRIMER' do.
    clamp=.gc_count (-(5<.length)){.sequence
    longest=.1
    current=.1
    tandem=.0
    for_k. 1+i.length-1 do.
      if. (k{sequence)=(k-1){sequence do. current=.current+1 else. current=.1 end.
      longest=.longest>.current
      if. (k{sequence)~:(k-1){sequence do. tandem=.tandem>.((k-1),2)repeat_count sequence end.
    end.
    selfcomp=.0
    for_center. i.length-1 do.
      left=.center
      right=.center+1
      while. (left>:0)*.right<length do.
        if. -.((complement left{sequence)text_equal right{sequence) do. break. end.
        selfcomp=.selfcomp>.(1+right-left)
        left=.left-1
        right=.right+1
      end.
    end.
    gc=.gc_count sequence
    tm=.melting_temperature sequence
    names=.;:'length gc tm clamp run repeat selfcomp'
    values=.(<number length),(<gc percentage length),(<tenths tm),(<number clamp),(<number longest),(<number tandem),<number selfcomp
    passed=.((length>:18)*.length<:25),(((40*length)<:100*gc)*.(100*gc)<:60*length),((tm>:520)*.tm<:620),((clamp>:1)*.clamp<:3),(longest<:4),(tandem<:4),selfcomp<:6
    output=.0$a:
    failed=.0$a:
    for_k. i.7 do.
      if. k{passed do. verdict=.' OK' else. verdict=.' FAIL' end.
      output=.output,<(k{::names),' ',(k{::values),verdict
      if. -.k{passed do. failed=.failed,k{names end.
    end.
    if. 0=#failed do. output,<'PASS' else. output,<'FAIL ',' 'join failed end.
  end.
)
main=:3:0
  initialize''
  input=.1!:1(3)
  if. LF~:{:input do. input=.input,LF end.
  lines=.<;._2 input
  count=.0".0{::lines
  for_k. 1+i.count do.
    output=.execute k{::lines
    for_line. output do. ((>line),LF)1!:2(4) end.
  end.
)
main''
