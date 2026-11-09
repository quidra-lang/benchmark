ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'sam_writer.ijs'
load SourceDirectory,'sequence_io.ijs'
load SourceDirectory,'suffix_array.ijs'
load SourceDirectory,'fm_index.ijs'
load SourceDirectory,'search.ijs'
align =: 3 : 0
 'w r c' =. y
 s =. r{::Refs
 l =. #w
 m =. #s
 band =. pn 'BAND_WIDTH'
 'a b go ge' =. pv 'SCORES'
 h =. e =. f =. ((l+1),m+1)$_1000000
 for_j. i.m+1 do. if. band>:|j-c do. h =. 0(<0,j)}h end. end.
 for_i. 1+i.l do.
  for_j. (0>.i+c-band)+i.1+(m<.i+c+band)-0>.i+c-band do.
   fv =. (((<(i-1),j){h)-go+ge)>.((<(i-1),j){f)-ge
   f =. fv(<i,j)}f
   ev =. _1000000
   diag =. _1000000
   if. j>0 do.
    ev =. (((<i,j-1){h)-go+ge)>.((<i,j-1){e)-ge
    match =. ((i-1){w)=(j-1){s
    score =. match{(-b),a
    diag =. ((<(i-1),j-1){h)+score
   end.
   e =. ev(<i,j)}e
   h =. (diag>.ev>.fv)(<i,j)}h
  end.
 end.
 vals =. l{h
 sc =. >./vals
 if. sc<:_900000 do. i.0 return. end.
 j =. vals i.sc
 i =. l
 state =. 'H'
 ops =. ''
 while. i>0 do.
  if. state='H' do.
   diag =. 0
   if. j>0 do.
    score =. (((i-1){w)=(j-1){s){(-b),a
    diag =. ((<i,j){h)=((<(i-1),j-1){h)+score
   end.
   if. diag do. ops =. 'M',ops
   i =. i-1
   j =. j-1
   elseif. ((<i,j){h)=(<i,j){f do. state =. 'I'
   else. state =. 'D' end.
  elseif. state='I' do.
   stay =. ((<i,j){f)=((<(i-1),j){f)-ge
   ops =. 'I',ops
   i =. i-1
   if. -.stay do. state =. 'H' end.
  else.
   stay =. ((<i,j){e)=((<i,j-1){e)-ge
   ops =. 'D',ops
   j =. j-1
   if. -.stay do. state =. 'H' end.
  end.
 end.
 sc;j;ops
)
describe =: 3 : 0
 'w r pos strand ops trimmed' =. y
 ref =. r{::Refs
 i =. 0
 j =. pos
 u =. 0
 nm =. 0
 md =. cigar =. ''
 pairs =. 0 2$0
 k =. 0
 while. k<#ops do.
  ch =. k{ops
  end =. k+1
  while. end<#ops do. if. ch~:end{ops do. break. end.
  end =. end+1 end.
  cigar =. cigar,(str end-k),ch
  if. ch='D' do.
   md =. md,(str u),'^',(j+i.end-k){ref
   u =. 0
   j =. j+end-k
   nm =. nm+end-k
  elseif. ch='I' do. i =. i+end-k
  nm =. nm+end-k
  else.
   for_step. i.end-k do.
    pairs =. pairs,i,j
    if. (i{w)=j{ref do. u =. u+1
    else. md =. md,(str u),j{ref
    u =. 0
    nm =. nm+1 end.
    i =. i+1
    j =. j+1
   end.
  end.
  k =. end
 end.
 md =. md,str u
 if. trimmed do.
  soft =. (str trimmed),'S'
  if. strand do. cigar =. soft,cigar else. cigar =. cigar,soft end.
 end.
 cigar;nm;md;pairs
)
map_read =: 3 : 0
 'name full qual' =. y
 qs =. (a.i.qual)-33
 l =. #full
 while. l>0 do. if. ((l-1){qs)>:pn 'TRIM_QUALITY' do. break. end.
 l =. l-1 end.
 trimmed =. (#full)-l
 wplus =. l{.full
 orientations =. wplus;reverse_complement wplus
 reason =. 'SHORT'
 method =. ''
 hits =. 0 4$0
 alts =. 0$a:
 targets =. i.0
 x0 =. x1 =. mapq =. sc =. 0
 r =. pos =. strand =. 0
 ops =. ''
 if. l>:pn 'MIN_READ_LENGTH' do.
  reason =. 'NOHIT'
  exact =. 0
  for_w. orientations do. interval =. Forward backward >w
  exact =. exact+({.interval)<{:interval end.
  z =. pn 'MAX_MISMATCHES'
  if. exact do. z =. 1 end.
  for_str. i.2 do.
   found =. z backtrack str{::orientations
   for_hit. found do.
    'p mm' =. hit
    'rr pp' =. reference_position p
    if. rr>:0 do. hits =. hits,mm,rr,pp,str end.
   end.
  end.
  if. #hits do.
   hits =. (/:hits){hits
   'best r pos strand' =. 0{hits
   x0 =. +/best=0{"1 hits
   x1 =. +/(best+1)=0{"1 hits
   method =. (best>0){::'EXACT';'MISMATCH'
   ops =. l#'M'
   'a b go ge' =. pv 'SCORES'
   sc =. ((l-best)*a)-best*b
   mapq =. 0
   if. x0=1 do.
    if. x1=0 do. mapq =. 60-12*best else. mapq =. 1>.(30-(12*best))-3*x1 end.
   end.
   for_hit. }.hits#~(0{"1 hits)<:best+1 do.
    'mm rr pp st' =. hit
    alts =. alts,<rr;pp;st;ops
   end.
   targets =. /:~~.(best=0{"1 hits)#1{"1 hits
  elseif. l>:pn 'SEED_LENGTH' do.
   ls =. pn 'SEED_LENGTH'
   step =. pn 'SEED_STEP'
   candidates =. 0 3$0
   SeedTotals =: SeedTotals+1 0 0 0 0 0 0
   for_st. i.2 do.
    w =. st{::orientations
    for_o. step*i.1+<.(l-ls)%step do.
     SeedTotals =: SeedTotals+0 1 0 0 0 0 0
     seed =. ls{.o}.w
     if. 'N'e.seed do. SeedTotals =: SeedTotals+0 0 1 0 0 0 0
     continue. end.
     'lo hi' =. Forward backward seed
     if. (hi-lo)>pn 'MAX_SEED_HITS' do. SeedTotals =: SeedTotals+0 0 0 1 0 0 0
     continue. end.
     if. hi=lo do. SeedTotals =: SeedTotals+0 0 0 0 1 0 0
     continue. end.
     for_row. lo+i.hi-lo do.
      'rr pp' =. reference_position {.Forward locate row
      candidates =. candidates,st,rr,pp-o
     end.
    end.
   end.
   candidates =. /:~~.candidates
   SeedTotals =: SeedTotals+0 0 0 0 0,(#candidates),0
   accepted =. 0$a:
   keys =. 0 4$0
   for_cand. candidates do.
    'st rr c' =. cand
    result =. align (st{::orientations);rr;c
    if. 0=#result do. continue. end.
    'score pp operations' =. result
    if. (100*score)<(pn 'MIN_SCORE_PERCENT')*({.pv 'SCORES')*l do. continue. end.
    key =. rr,pp,st
    previous =. _1
    for_i. i.#accepted do. if. key-:1 2 3{i{keys do. previous =. i
    break. end. end.
    if. previous<0 do.
     accepted =. accepted,<rr;pp;st;operations
     keys =. keys,(-score),rr,pp,st
    elseif. score>-(<previous,0){keys do.
     accepted =. (<rr;pp;st;operations)previous}accepted
     keys =. ((-score),rr,pp,st)previous}keys
    end.
   end.
   SeedTotals =: SeedTotals+0 0 0 0 0 0,#accepted
   if. #accepted do.
    ord =. /:keys
    keys =. ord{keys
    accepted =. ord{accepted
    'r pos strand ops' =. 0{::accepted
    sc =. -(<0,0){keys
    x0 =. +/(-sc)=0{"1 keys
    x1 =. (#keys)-x0
    second =. 0
    if. x1 do. second =. -(<x0,0){keys end.
    if. x0=1 do. mapq =. <.(60*(sc-second))%sc end.
    method =. 'SEED'
    alts =. }.accepted
    targets =. /:~~.x0{.1{"1 keys
   end.
  end.
 end.
 mapped =. #method
 if. mapped do. reason =. '' end.
 name;full;qual;l;trimmed;reason;method;r;pos;strand;ops;sc;x0;x1;mapq;alts;targets
)
index_report =: 3 : 0
 n =. #Text
 ls =. pn 'SEED_LENGTH'
 out =. <emit 'text length';n;'sequences';#Refs
 for_r. i.#Refs do. out =. out,<emit 'sequence';(r{::RefNames);'length';(r{RefLengths);'offset';(r{Offsets);'gc';((+/ (r{::Refs)e.'GC')ratio r{RefLengths);'masked';r{Masked end.
 row =. <'symbols'
 for_ch. Symbols do. row =. row,(<,ch),<+/Text=ch end.
 out =. out,<emit row
 'sa classes' =. 1 2{Forward
 sa =. >sa
 classes =. >classes
 'ordered lcp' =. Text check_sa sa
 maxl =. >./lcp
 imax =. 1+lcp i.maxl
 kmers =. 0$a:
 for_r. Refs do.
  s =. >r
  for_p. i.0>.1+(#s)-ls do. kmers =. kmers,<ls{.p}.s end.
 end.
 unique =. ~.kmers
 counts =. +/"1 unique=/kmers
 steps =. i.0
 correct =. 0
 for_i. i.n do. 'p st' =. Forward locate i
 steps =. steps,st
 correct =. correct+p=i{sa end.
 runs =. 1++/(}.3{::Forward)~:}:3{::Forward
 out =. out,(<''),(<'forward_index'),<emit 'suffix_array rounds';(#classes)-1
 for_t. i.#classes do. out =. out,<emit 'round';t;'prefix_length';(2^t);'classes';t{classes end.
 out =. out,<emit 'sa_check pairs';(n-1);'ordered';ordered;'lcp_sum';(+/lcp);'mean_lcp';((+/lcp)ratio n-1);'max_lcp';maxl
 out =. out,<emit 'longest_repeat';maxl;(position_name (imax-1){sa);position_name imax{sa
 out =. out,<emit 'kmers length';ls;'occurrences';(#kmers);'distinct';(#unique);'unique';(+/counts=1);'max_occurrence';(>./0,counts);'unique_fraction';(+/counts=1)ratio #kmers
 out =. out,<emit 'bwt runs';runs;'head';(60<.#3{::Forward){.3{::Forward
 row =. <'c_array'
 for_i. i.6 do. row =. row,(<,i{Symbols),<i{4{::Forward end.
 out =. out,<emit row
 ncheck =. #5{::Forward
 samples =. +/(6{::Forward)>:_0
 out =. out,(<emit 'occ interval';(pn 'OCC_INTERVAL');'checkpoints';ncheck),(<emit 'sa_sample interval';(pn 'SA_SAMPLE_INTERVAL');'samples';samples),(<emit 'locate rows';n;'correct';correct;'total_steps';(+/steps);'max_steps';(>./steps);'mean_steps';(+/steps)ratio n),<emit 'inverse_bwt identical';(Text-:inverse Forward){::'no';'yes'
 'ro rl' =. RevText check_sa 1{::Reverse
 out =. out,(<''),(<'reverse_index'),(<emit 'suffix_array rounds';(_1+#2{::Reverse)),(<emit 'sa_check pairs';(n-1);'ordered';ro),(<emit 'bwt runs';(1++/(}.3{::Reverse)~:}:3{::Reverse);'head';(60<.#3{::Reverse){.3{::Reverse),<emit 'inverse_bwt identical';(RevText-:inverse Reverse){::'no';'yes'
 out =. out,(<''),<'direct_sort'
 count =. 0
 for_r. i.#Refs do.
  s =. (r{::Refs),'$'
  if. (r{RefLengths)<:pn 'DIRECT_SORT_LIMIT' do.
   'sa cs' =. suffix_array s
   out =. out,<emit (r{::RefNames);'length';(#s);'rounds';(#cs)-1;'identical';(sa-:direct_sort s){::'no';'yes'
   count =. count+1
  end.
 end.
 if. count=0 do. out =. out,<'none' end.
 bitmap =. <.(n+7)%8
 total =. n+(24*ncheck)+(4*samples)+bitmap
 out,(<''),<emit 'index_size bwt_bytes';n;'occ_bytes';(24*ncheck);'sample_bytes';(4*samples);'bitmap_bytes';bitmap;'total_bytes';total;'full_bytes';(5*n);'ratio';total ratio 5*n
)
main =: 3 : 0
 read_sequences ''
 1!:5 :: 0: <'output'
 Forward =: build_index Text
 Reverse =: build_index RevText
 SearchTotals =: 4$0
 SeedTotals =: 7$0
 mapped =. 0$a:
 for_read. Reads do. mapped =. mapped,<map_read >read end.
 depth =. zero =. pile =. 0$a:
 for_ref. Refs do.
  m =. #>ref
  depth =. depth,<m$0
  zero =. zero,<m$0
  pile =. pile,<(m,2,4)$0
 end.
 maxlen =. >./#@:(1&{::)&>Reads
 cycles =. (maxlen,2)$0
 subst =. 4 5$0
 qbins =. 5 2$0
 qcount =. qsum =. 2$0
 cigarcounts =. 4$0
 indels =. 4$0
 sam =. sam_header ''
 'vd vq vp vh' =. pv 'VARIANTS'
 for_rec. mapped do.
  'name full qual l trim reason method r pos strand ops score x0 x1 mapq alts targets' =. >rec
  if. 0=#method do.
   sam =. sam,<TAB join name;4;'*';0;0;'*';'*';0;0;full;qual;'YM:Z:',reason
   continue.
  end.
  w =. l{.full
  seq =. full
  quality =. qual
  qs =. (a.i.qual)-33
  if. strand do. w =. reverse_complement w
  seq =. reverse_complement full
  quality =. |.qual end.
  'cigar nm md pairs' =. describe w;r;pos;strand;ops;trim
  fields =. name;(16*strand);(r{::RefNames);(pos+1);mapq;cigar;'*';0;0;seq;quality;('NM:i:',str nm);('MD:Z:',md);('AS:i:',str score);('X0:i:',str x0);('X1:i:',str x1);'YM:Z:',method
  if. (#alts)*.(#alts)<:pn 'MAX_ALT_HITS' do.
   xa =. 'XA:Z:'
   for_alt. alts do.
    'rr pp st oo' =. >alt
    ww =. l{.full
    if. st do. ww =. reverse_complement ww end.
    ad =. describe ww;rr;pp;st;oo;trim
    xa =. xa,(rr{::RefNames),',',(st{'+-'),(str pp+1),',',(0{::ad),',',(str 1{::ad),';'
   end.
   fields =. fields,<xa
  end.
  sam =. sam,<TAB join fields
  cigarcounts =. cigarcounts+(+/ops='M'),(+/ops='I'),(+/ops='D'),trim
  if. mapq=0 do. zz =. r{::zero
  zz =. (1+pos{zz)pos}zz
  zero =. (<zz)r}zero end.
  dep =. r{::depth
  counts =. r{::pile
  ref =. r{::Refs
  for_pair. pairs do.
   'i j' =. pair
   cycle =. i
   if. strand do. cycle =. l-i-1 end.
   qualityvalue =. cycle{qs
   mismatch =. (i{w)~:j{ref
   if. mapq>:pn 'COVERAGE_MIN_MAPQ' do.
    dep =. (1+j{dep)j}dep
    if. ((i{w)~:'N')*.qualityvalue>:vq do.
     b =. 'ACGT'i.i{w
     counts =. (1+(<j,strand,b){counts)(<j,strand,b)}counts
    end.
   end.
   if. x0=1 do.
    cycles =. (1+(<cycle,0){cycles)(<cycle,0)}cycles
    cycles =. (mismatch+(<cycle,1){cycles)(<cycle,1)}cycles
    rb =. 'ACGT'i.j{ref
    wb =. 'ACGTN'i.i{w
    subst =. (1+(<rb,wb){subst)(<rb,wb)}subst
    qb =. 4<.<.qualityvalue%10
    qbins =. (1+(<qb,0){qbins)(<qb,0)}qbins
    qbins =. (mismatch+(<qb,1){qbins)(<qb,1)}qbins
    qcount =. (1+mismatch{qcount)mismatch}qcount
    qsum =. (qualityvalue+mismatch{qsum)mismatch}qsum
   end.
  end.
  depth =. (<dep)r}depth
  pile =. (<counts)r}pile
  if. x0=1 do.
   for_ch. 'ID' do.
    mask =. ops=ch
    events =. +/mask*.-.0,}:mask
    k =. 2*'ID'i.ch
    indels =. ((k{indels)+events)k}indels
    indels =. (((k+1){indels)++/mask)(k+1)}indels
   end.
  end.
 end.
 'alignments.sam'write sam
 'index_stats.txt'write index_report ''
 cov =. <emit 'window';(pn 'COVERAGE_WINDOW');'min_mapq';pn 'COVERAGE_MIN_MAPQ'
 variants =. <emit 'min_depth';vd;'min_base_quality';vq;'min_alt_percent';vp;'hom_percent';vh
 callable =. nv =. hom =. 0
 for_r. i.#Refs do.
  dep =. r{::depth
  ref =. r{::Refs
  m =. #ref
  name =. r{::RefNames
  cov =. cov,<emit 'reference';name;'length';m;'covered';(+/dep>0);'breadth';((+/dep>0)ratio m);'mean_depth';((+/dep)ratio m);'max_depth';>./dep
  histogram =. <'depth_histogram'
  for_d. i.1+>./dep do. histogram =. histogram,<(str d),':',str +/dep=d end.
  cov =. cov,<emit histogram
  wc =. pn 'COVERAGE_WINDOW'
  for_start. wc*i.>.m%wc do.
   ids =. start+i.wc<.m-start
   values =. ids{dep
   total =. +/values
   cov =. cov,<emit name;(start+1);(1+{:ids);'gc';((+/(ids{ref)e.'GC')ratio #ids);'sum';total;'mean';(total ratio #ids);'max';(>./values);'zero';(+/values=0);'mapq0';(+/ids{r{::zero);'|',(<.(10*total)%#ids)#'#'
  end.
  for_j. i.m do.
   counts =. +/j{r{::pile
   dp =. +/counts
   if. dp<vd do. continue. end.
   callable =. callable+1
   alternatives =. (i.4)-.'ACGT'i.j{ref
   b =. (alternatives{counts)i.>./alternatives{counts
   b =. b{alternatives
   alt =. b{counts
   if. (alt>:2)*.(100*alt)>:vp*dp do.
    homo =. (100*alt)>:vh*dp
    hom =. hom+homo
    nv =. nv+1
    strands =. b{"1 j{r{::pile
    variants =. variants,<emit name;(j+1);((j{ref),'>',b{'ACGT');'depth';dp;'alt';alt;'fraction';(alt ratio dp);'genotype';(homo{::'0/1';'1/1');'strands';(emit <"0 strands);'counts';emit <"0 counts
   end.
  end.
 end.
 variants =. variants,<emit 'callable';callable;'variants';nv;'heterozygous';(nv-hom);'homozygous';hom
 'coverage.txt'write cov
 'variants.txt'write variants
 flags =. 0<#@:(6&{::)&>mapped
 unique =. flags*.1=12{::&>mapped
 lengths =. 3{::&>mapped
 trims =. 4{::&>mapped
 reasons =. 5{&>mapped
 methods =. 6{&>mapped
 strands =. 9{::&>mapped
 references =. 7{::&>mapped
 mapqs =. 14{::&>mapped
 summary =. (<emit 'reads total';(#Reads);'trimmed';(+/trims>0);'trimmed_bases';(+/trims);'short';+/(<'SHORT')=reasons),(<emit 'mapped';(+/flags);'rate';((+/flags)ratio #Reads);'unique';(+/unique);'multi';(+/flags*.-.unique);'unmapped';+/-.flags),(<emit 'unmapped short';(+/(<'SHORT')=reasons);'nohit';+/(<'NOHIT')=reasons),(<emit 'method exact';(+/(<'EXACT')=methods);'mismatch';(+/(<'MISMATCH')=methods);'seed';+/(<'SEED')=methods),<emit 'strand forward';(+/flags*.strands=0);'reverse';+/flags*.strands=1
 for_r. i.#Refs do. mask =. flags*.references=r
 summary =. summary,<emit 'reference';(r{::RefNames);'mapped';(+/mask);'unique';(+/mask*.unique);'forward';(+/mask*.strands=0);'reverse';+/mask*.strands=1 end.
 summary =. summary,<'length_bins'
 for_lo. 10*((<.(<./lengths)%10)+i.1+(<.(>./lengths)%10)-<.(<./lengths)%10) do.
  mask =. (lengths>:lo)*.lengths<:lo+9
  summary =. summary,<emit ((str lo),'-',str lo+9);'reads';(+/mask);'mapped';(+/mask*.flags);'unique';+/mask*.unique
 end.
 ns =. nbs =. i.0
 for_read. Reads do. seq =. 1{::>read
 ns =. ns,'N'e.seq
 nbs =. nbs,+/seq='N' end.
 summary =. summary,<emit 'n_reads';(+/ns);'n_bases';(+/nbs);'mapped';+/ns*.flags
 summary =. summary,<'multi_targets'
 sets =. 0$a:
 for_i. I.flags*.-.unique do. sets =. sets,< '+'join (16{::i{::mapped){RefNames end.
 if. #sets do. for_name. /:~~.sets do. summary =. summary,<emit (>name);+/sets=name end.
 else. summary =. summary,<'none' end.
 summary =. summary,<'mapq_histogram'
 for_q. \:~~.flags#mapqs do. summary =. summary,<emit q;+/flags*.mapqs=q end.
 nms =. i.0
 for_i. I.flags do.
  rec =. i{::mapped
  ww =. (3{::rec){.1{::rec
  if. 9{::rec do. ww =. reverse_complement ww end.
  desc =. describe ww;(7{::rec);(8{::rec);(9{::rec);(10{::rec);4{::rec
  nms =. nms,1{::desc
 end.
 summary =. summary,<'nm_histogram'
 for_nm. /:~~.nms do. summary =. summary,<emit nm;+/nms=nm end.
 aligned =. +/,subst
 mismatches =. 1{qcount
 summary =. summary,(<emit 'error_profile aligned_bases';aligned;'mismatches';mismatches;'rate';mismatches ratio aligned),(<'substitutions'),<'ref A C G T N'
 for_i. i.4 do. summary =. summary,<emit (,i{'ACGT');emit <"0 i{subst end.
 summary =. summary,<'mismatch_by_cycle'
 for_i. i.maxlen do. 'a b' =. i{cycles
 summary =. summary,<emit 'cycle';(i+1);'aligned';a;'mismatches';b;'rate';b ratio a end.
 summary =. summary,(<emit 'quality matched';(0{qcount);'mean';((0{qsum)ratio 0{qcount);'mismatched';(1{qcount);'mean';(1{qsum)ratio 1{qcount),<'quality_bins'
 for_i. i.5 do. 'a b' =. i{qbins
 summary =. summary,<emit (i{::'0-9';'10-19';'20-29';'30-39';'40-');'aligned';a;'mismatches';b;'rate';b ratio a end.
 summary =. summary,<emit 'cigar M';(0{cigarcounts);'I';(1{cigarcounts);'D';(2{cigarcounts);'S';3{cigarcounts
 summary =. summary,<emit 'indels insertions';(0{indels);(1{indels);'deletions';(2{indels);3{indels
 summary =. summary,<emit 'search dfs_calls';(0{SearchTotals);'dfs_nodes';(1{SearchTotals);'dfs_leaves';(2{SearchTotals);'dfs_positions';3{SearchTotals
 summary =. summary,<emit 'seeds reads';(0{SeedTotals);'seeds';(1{SeedTotals);'with_n';(2{SeedTotals);'repetitive';(3{SeedTotals);'without_hit';(4{SeedTotals);'candidates';(5{SeedTotals);'passing';6{SeedTotals
 'summary.txt'write summary
 i.0 0
)
main ''
