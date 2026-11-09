ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'tree_io.ijs'
load SourceDirectory,'alignment.ijs'
load SourceDirectory,'distances.ijs'
load SourceDirectory,'tree_building.ijs'
load SourceDirectory,'parsimony.ijs'
sum =: 3 : 0
 total =. 0.0
 for_v. y do. total =. total+v end.
 total
)
mean =: 3 : '(sum y)%#y'
rf =: 4 : '#(x-.y),y-.x'
bme =: 3 : 0
 leaves =. /:~2{::y
 total =. 0.0
 for_i. leaves do.
  counts =. 1{::y path_distances i
  for_j. leaves#~leaves>i do. total =. total+((<i,j){MainDistances)%(2^(_1+j{counts)) end.
 end.
 total
)
objective =: 4 : 0
 if. x do. bme y else. +/fitch y end.
)
hill_climb =: 3 : 0
 'kind tree' =. y
 current =. kind objective tree
 moves =. 0 3$0.0
 evaluated =. 0
 while. 1 do.
  improved =. 0
  for_candidate. nni_candidates tree do.
   'mask swap next' =. >candidate
   value =. kind objective next
   evaluated =. evaluated+1
   if. value<current do.
    tree =. next
    current =. value
    moves =. moves,mask,swap,value
    improved =. 1
    break.
   end.
  end.
  if. -.improved do. break. end.
 end.
 tree;moves;evaluated
)
stepwise =: 3 : 0
 taxa =. y
 tree =. initial_tree 3{.taxa
 lines =. <emit 'START';((0{taxa){::Names);((1{taxa){::Names);((2{taxa){::Names);'score';+/fitch tree
 evaluated =. 0
 for_taxon. 3}.taxa do.
  best =. _
  ties =. 0
  for_edge. branches tree do.
   candidate =. insert_taxon tree;edge;taxon
   score =. +/fitch candidate
   evaluated =. evaluated+1
   if. score<best do. best =. score
   chosen =. candidate
   chosenmask =. {.edge
   ties =. 1
   elseif. score=best do. ties =. ties+1 end.
  end.
  tree =. chosen
  lines =. lines,<emit 'ADD';(taxon{::Names);'edge';(symbol chosenmask);'score';best;'ties';ties
 end.
 tree;lines;evaluated
)
all_trees =: 3 : 0
 trees =. <initial_tree 3{.y
 for_taxon. 3}.y do.
  next =. 0$a:
  for_tree. trees do.
   tree =. >tree
   for_edge. branches tree do. next =. next,<insert_taxon tree;edge;taxon end.
  end.
  trees =. next
 end.
 trees
)
likelihood =: 3 : 0
 'adj lengths leaves negatives' =. y
 'root parent order masks' =. rooting y
 sites =. i.0
 for_col. i.L do.
  partial =. ((#adj),4)$0.0
  for_node. |.order do.
   if. node e.leaves do.
    mask =. (<node,col){Sets
    row =. 0<mask(17 b.)1 2 4 8
   else.
    row =. 4$1.0
    children =. y children_order node;(node{parent);masks
    for_child. children do.
     length =. (<node,child){lengths
     e =. ^-((4*length)%3)
     u =. 4$0.0
     for_a. i.4 do.
      value =. 0.0
      for_b. i.4 do.
       if. a=b do. prob =. 0.25+0.75*e else. prob =. 0.25-0.25*e end.
       value =. value+prob*(<child,b){partial
      end.
      u =. value a}u
     end.
     row =. row*u
    end.
   end.
   partial =. row node}partial
  end.
  sites =. sites,^.sum 0.25*root{partial
 end.
 sites
)
parsimony_bounds =: 3 : 0
 minimum =. maximum =. i.0
 for_c. i.L do.
  sets =. c{"1 Sets
  best =. 4
  for_mask. 1+i.15 do. if. *./0<mask(17 b.)sets do. best =. best<.bitcount mask end. end.
  minimum =. minimum,best-1
  values =. i.0
  for_base. 1 2 4 8 do. values =. values,+/0=base(17 b.)sets end.
  maximum =. maximum,<./values
 end.
 minimum;maximum
)
quartets =: 3 : 0
 ss =. splits y
 topologies =. i.0
 for_a. i.N do.
  for_b. (a+1)+i.(N-a)-1 do.
   for_c. (b+1)+i.(N-b)-1 do.
    for_d. (c+1)+i.(N-c)-1 do.
     topology =. 0
     pairings =. ((2^a)+(2^b)),((2^a)+(2^c)),(2^a)+2^d
     all =. +/2^a,b,c,d
     for_i. i.3 do.
      first =. i{pairings
      other =. all-first
      for_mask. ss do.
       hit =. (mask(17 b.)all)
       if. (hit=first)+.hit=other do. topology =. i+1
       break. end.
      end.
      if. topology do. break. end.
     end.
     topologies =. topologies,topology
    end.
   end.
  end.
 end.
 topologies
)
matrix_lines =: 3 : 0
 width =. >./#&>Names
 out =. 0$a:
 for_i. i.N do.
  text =. width{.(i{::Names),width#' '
  for_v. i{y do. text =. text,' ',5 fmt v end.
  out =. out,<text
 end.
 out
)
main =: 3 : 0
 read_alignment ''
 summary =. (<emit 'INPUT records';(#RecordNames);'accepted';N;'rejected';(#Rejects);'columns';L),Rejects
 basecounts =. 4$0
 classes =. 5$0
 for_i. i.N do.
  seq =. i{Alignment
  counts =. +/"1 'ACGT'=/seq
  basecounts =. basecounts+counts
  bases =. +/counts
  ambiguous =. +/seq e.'RYSWKMBDHV'
  missing =. +/seq e.'N-'
  unique =. 0
  for_c. i.L do.
   ch =. c{seq
   others =. ((i.N)-.i){c{"1 Alignment
   if. (ch e.'ACGT')*.(+./others e.'ACGT')*.-.ch e.others do. unique =. unique+1 end.
  end.
  summary =. summary,<emit 'TAXON';(i{::Names);'bases';bases;'ambiguous';ambiguous;'missing';missing;'unique';unique;'gc';4 fmt ((1{counts)+2{counts)%bases
 end.
 for_column. |:Alignment do. classes =. classes+column_classes column end.
 summary =. summary,<emit 'COLUMNS constant';(0{classes);'variable';(1{classes);'informative';(2{classes);'gapped';(3{classes);'empty';4{classes
 summary =. summary,<emit 'PATTERNS';#Patterns
 text =. 'COMPOSITION'
 for_i. i.4 do. text =. text,' ',(i{'ACGT'),' ',4 fmt (i{basecounts)%+/basecounts end.
 summary =. summary,<text
 Distances =: Saturated =: NJTrees =: 0$a:
 for_model. i.3 do.
  'matrix saturated paircounts' =. model distance_matrix L$1
  Distances =: Distances,<matrix
  Saturated =: Saturated,<saturated
  NJTrees =: NJTrees,<matrix neighbor_joining i.N
 end.
 MainDistances =: MainModel{::Distances
 mainnj =. MainModel{::NJTrees
 mainname =. 'NJ_',Model
 MethodNames =: 'NJ_P';'NJ_JC';'NJ_K2P';'ME';'MP';'CONSENSUS'
 'metree memoves meevaluated' =. hill_climb 1;mainnj
 'stepwise_tree steplines stepevaluated' =. stepwise Outgroup,Ingroup
 'mptree mpmoves mpevaluated' =. hill_climb 0;stepwise_tree
 'mptree ancestral MPChanges' =. reconstruct mptree
 exhaust =. all_trees ExhaustiveTaxa
 escores =. ebmes =. i.0
 enewicks =. esplits =. 0$a:
 for_tree. exhaust do.
  tree =. >tree
  escores =. escores,+/fitch tree
  ebmes =. ebmes,bme tree
  enewicks =. enewicks,<newick tree;0
  esplits =. esplits,<splits tree
 end.
 bestscore =. <./escores
 optimalids =. I.escores=bestscore
 optimalids =. (/:optimalids{enewicks){optimalids
 strict =. {.optimalids{esplits
 strict =. >strict
 for_i. }.optimalids do. strict =. strict#~strict e.i{::esplits end.
 stricttree =. consensus_tree ExhaustiveTaxa;strict
 'ehstep ehsteps eheval' =. stepwise ExhaustiveTaxa
 'ehheuristic ehmoves ehevaluated' =. hill_climb 0;ehstep
 bmeorder =. /:enewicks
 bmeorder =. (/:bmeorder{ebmes){bmeorder
 bmebest =. 0{bmeorder
 bmesecond =. 1{bmeorder
 Supports =: (2^N)$0
 bootstraplines =. <emit 'BOOTSTRAP model';Model;'replicates';Replicates;'seed';Seed
 rng =. Seed
 mainsplits =. splits mainnj
 identical =. 0
 for_b. 1+i.Replicates do.
  weights =. L$0
  for_draw. i.L do.
   rng =. 2147483647|48271x*rng
   col =. L|rng
   weights =. (1+col{weights)col}weights
  end.
  matrix =. 0{::MainModel distance_matrix weights
  tree =. matrix neighbor_joining i.N
  ss =. splits tree
  Supports =: (1+ss{Supports)ss}Supports
  distance =. mainsplits rf ss
  identical =. identical+distance=0
  bootstraplines =. bootstraplines,<emit 'REPLICATE';b;'distinct';(+/weights>0);'rf';distance
 end.
 bootstraplines =. bootstraplines,<emit 'IDENTICAL';identical
 for_mask. mask_order mainsplits do. bootstraplines =. bootstraplines,<emit 'SUPPORT';(symbol mask);mask{Supports end.
 allsupport =. mask_order I.Supports>0
 allsupport =. (\:allsupport{Supports){allsupport
 for_mask. allsupport do. bootstraplines =. bootstraplines,<emit 'SPLIT';(symbol mask);mask{Supports end.
 majority =. I.(2*Supports)>Replicates
 consensustree =. consensus_tree (i.N);majority
 bootstraplines =. bootstraplines,<emit 'CONSENSUS';newick consensustree;2
 for_taxon. Ingroup do.
  leaves =. (i.N)-.taxon
  tree =. MainDistances neighbor_joining leaves
  reduced =. i.0
  for_mask. mainsplits do.
   new =. mask-(mask(17 b.)2^taxon)
   size =. bitcount new
   if. (size>:2)*.size<:N-3 do. reduced =. reduced,new end.
  end.
  bootstraplines =. bootstraplines,<emit 'JACKKNIFE';(taxon{::Names);'rf';(~.reduced)rf splits tree
 end.
 Trees =: NJTrees,(<metree),(<mptree),<consensustree
 SplitSets =: splits&.>Trees
 Likelihoods =: likelihood&.>NJTrees
 Scores =: 0$a:
 for_tree. 5{.Trees do. Scores =: Scores,<fitch >tree end.
 Scores =: Scores,<i.0
 'minimum maximum' =. parsimony_bounds ''
 minsum =. +/minimum
 maxsum =. +/maximum
 parsimony =. <emit 'BOUNDS minimum';minsum;'maximum';maxsum
 for_i. i.3 do.
  score =. +/i{::Scores
  parsimony =. parsimony,<emit 'TREE';(i{::MethodNames);'score';score;'ci';(4 fmt minsum%score);'ri';4 fmt (maxsum-score)%(maxsum-minsum)
 end.
 parsimony =. parsimony,steplines,<emit 'STEPWISE score';(+/fitch stepwise_tree);'evaluated';stepevaluated
 for_move. mpmoves do. parsimony =. parsimony,<emit 'NNI edge';(symbol 0{move);'swap';(1{move);'score';<.2{move end.
 mpscore =. +/4{::Scores
 parsimony =. parsimony,<emit 'SEARCH moves';(#mpmoves);'evaluated';mpevaluated;'score';mpscore
 parsimony =. parsimony,<emit 'TREE MP score';mpscore;'ci';(4 fmt minsum%mpscore);'ri';4 fmt (maxsum-mpscore)%(maxsum-minsum)
 parsimony =. parsimony,<emit 'MP';newick mptree;1
 changes =. 4{::Scores
 for_k. i.1+>./changes do. parsimony =. parsimony,<emit 'CHANGES';k;'columns';+/changes=k end.
 parsimony =. parsimony,<emit 'HOMOPLASY columns';(+/changes>minimum);'extra';mpscore-minsum
 'root parent order masks' =. rooting mptree
 internal =. order#~order>:N
 internal =. (/:symbol&.>internal{masks){internal
 for_node. internal do. parsimony =. parsimony,<emit 'ANCESTOR';(symbol node{masks);node{ancestral end.
 parsimony =. parsimony,(<''),<emit 'EXHAUSTIVE taxa';(#ExhaustiveTaxa);'trees';(#exhaust);'best';bestscore;'optimal';#optimalids
 for_score. /:~~.escores do. parsimony =. parsimony,<emit 'SCORE';score;'trees';+/escores=score end.
 for_i. optimalids do. parsimony =. parsimony,<emit 'OPTIMAL';(i{::enewicks);'bme';5 fmt i{ebmes end.
 parsimony =. parsimony,<emit 'STRICT';newick stricttree;0
 heuristic_score =. +/fitch ehheuristic
 parsimony =. parsimony,<emit 'HEURISTIC score';heuristic_score;'optimal';(heuristic_score=bestscore){::'no';'yes'
 distances =. 0$a:
 for_pair. paircounts do.
  'i j n s v' =. pair
  distances =. distances,<emit 'PAIR';(i{::Names);(j{::Names);'sites';n;'transitions';s;'transversions';v
 end.
 totals =. +/2 3 4{"1 paircounts
 distances =. distances,<emit 'TOTAL sites';(0{totals);'transitions';(1{totals);'transversions';2{totals
 for_i. i.3 do.
  distances =. distances,(<''),(<emit 'MODEL';i{::Models),matrix_lines i{::Distances
  for_sat. i{::Saturated do. 'a b n' =. sat
  distances =. distances,<emit 'SATURATED';(a{::Names);(b{::Names);'sites';n end.
 end.
 distances =. distances,(<''),(<emit 'PATRISTIC';mainname),matrix_lines patristic mainnj
 distances =. distances,(<''),<emit 'ME start';mainname;'length';5 fmt bme mainnj
 for_move. memoves do. distances =. distances,<emit 'NNI edge';(symbol 0{move);'swap';(1{move);'length';5 fmt 2{move end.
 distances =. distances,<emit 'ME moves';(#memoves);'evaluated';meevaluated;'length';5 fmt bme metree
 distances =. distances,<emit 'EXHAUSTIVE taxa';(#ExhaustiveTaxa);'trees';(#exhaust);'best';(5 fmt bmebest{ebmes);'second';5 fmt bmesecond{ebmes
 distances =. distances,<emit 'BEST';(bmebest{::enewicks);'parsimony';bmebest{escores
 likelihoodlines =. <emit 'LIKELIHOOD columns';L;'patterns';#Patterns
 for_i. i.3 do.
  ll =. sum i{::Likelihoods
  likelihoodlines =. likelihoodlines,<emit 'TREE';(i{::MethodNames);'loglik';(4 fmt ll);'per_site';4 fmt ll%L
 end.
 for_a. i.3 do. for_b. (a+1)+i.(3-a)-1 do.
  delta =. (a{::Likelihoods)-b{::Likelihoods
  difference =. sum delta
  average =. difference%L
  se =. %:(L%(L-1))*sum *:delta-average
  likelihoodlines =. likelihoodlines,<emit 'KH';(a{::MethodNames);(b{::MethodNames);'difference';(4 fmt difference);'se';(4 fmt se);'z';4 fmt difference%se
 end. end.
 sites =. MainModel{::Likelihoods
 rounded =. (*sites)*<.0.5+10000*|sites
 order =. /:rounded
 low =. (pn 'low_sites'){.order
 likelihoodlines =. likelihoodlines,<emit 'LOWEST';mainname;'sites';#low
 for_col. low do. likelihoodlines =. likelihoodlines,<emit 'SITE';(col+1);'loglik';(4 fmt col{sites);'changes';(col{MainModel{::Scores);'pattern';col{"1 Alignment end.
 treefile =. cladograms =. 0$a:
 for_i. i.6 do.
  mode =. 0
  if. i e.0 1 2 4 do. mode =. 1 elseif. i=5 do. mode =. 2 end.
  tree =. i{::Trees
  treefile =. treefile,<emit (i{::MethodNames);newick tree;mode
  if. #cladograms do. cladograms =. cladograms,<'' end.
  cladograms =. cladograms,cladogram (i{::MethodNames);tree
 end.
 clockrows =. 0$a:
 rejected =. pairnumber =. 0
 for_i. Ingroup do. for_j. Ingroup#~Ingroup>i do.
  m1 =. m2 =. 0
  for_c. i.L do.
   a =. (<i,c){Alignment
   b =. (<j,c){Alignment
   o =. (<Outgroup,c){Alignment
   if. *./(a,b,o)e.'ACGT' do.
    if. a~:b do. m1 =. m1+b=o
    m2 =. m2+a=o end.
   end.
  end.
  verdict =. 'ok'
  chi =. '-'
  if. m1+m2 do.
   chi =. 4 fmt (*:m1-m2)%(m1+m2)
   if. (1000**:m1-m2)>3841*(m1+m2) do. verdict =. 'reject'
   rejected =. rejected+1 end.
  end.
  pairnumber =. pairnumber+1
  clockrows =. clockrows,<emit 'RRT';(i{::Names);(j{::Names);'m1';m1;'m2';m2;'chi2';chi;verdict
 end. end.
 clock =. (<emit 'RELATIVE_RATE outgroup';(Outgroup{::Names);'pairs';pairnumber;'rejected';rejected),clockrows
 root =. 0{::rooting mainnj
 tips =. Ingroup{0{::mainnj path_distances root
 mu =. mean tips
 sd =. %:(sum *:tips-mu)%((#tips)-1)
 clock =. clock,<emit 'ROOT_TO_TIP';mainname;'mean';(5 fmt mu);'sd';(5 fmt sd);'cv';4 fmt sd%mu
 for_i. i.#Ingroup do. clock =. clock,<emit 'TIP';((i{Ingroup){::Names);5 fmt i{tips end.
 comparison =. 0$a:
 for_i. i.6 do.
  tree =. i{::Trees
  ss =. i{::SplitSets
  supported =. +/(2*ss{Supports)>Replicates
  score =. length =. bm =. negative =. sse =. ll =. '-'
  if. i<5 do. score =. str +/i{::Scores
  bm =. 5 fmt bme tree end.
  if. i<3 do.
   length =. 5 fmt (+/,1{::tree)%2
   negative =. str 3{::tree
   pat =. patristic tree
   error =. 0.0
   for_a. i.N do. for_b. (a+1)+i.(N-a)-1 do. error =. error+*:((<a,b){i{::Distances)-(<a,b){pat end. end.
   sse =. 6 fmt error
   ll =. 4 fmt sum i{::Likelihoods
  elseif. i=4 do. length =. 5 fmt mpscore%L end.
  comparison =. comparison,<emit 'TREE';(i{::MethodNames);'splits';(#ss);'supported';supported;'parsimony';score;'bme';bm;'length';length;'negative';negative;'sse';sse;'loglik';ll
 end.
 comparison =. comparison,<emit 'RF';' 'join MethodNames
 for_i. i.6 do.
  values =. i.0
  for_j. i.6 do. values =. values,(i{::SplitSets)rf j{::SplitSets end.
  comparison =. comparison,<emit (i{::MethodNames);emit <"0 values
 end.
 Quartets =: quartets&.>Trees
 comparison =. comparison,<emit 'QUARTET';' 'join MethodNames
 for_i. i.6 do.
  values =. i.0
  for_j. i.6 do. values =. values,+/(i{::Quartets)~:j{::Quartets end.
  comparison =. comparison,<emit (i{::MethodNames);emit <"0 values
 end.
 allclades =. mask_order ~.;SplitSets
 mainbranches =. branches mainnj
 mpbranches =. branches mptree
 for_mask. allclades do.
  marks =. ''
  for_ss. SplitSets do. marks =. marks,(mask e.>ss){'-+' end.
  length =. changes =. '-'
  rows =. mainbranches#~mask=0{"1 mainbranches
  if. #rows do. row =. {.rows
  length =. 5 fmt (<(1{row),2{row){1{::mainnj end.
  rows =. mpbranches#~mask=0{"1 mpbranches
  if. #rows do. row =. {.rows
  changes =. str (<(1{row),2{row){MPChanges end.
  comparison =. comparison,<emit 'CLADE';(symbol mask);'support';(mask{Supports);'trees';marks;'length';length;'changes';changes
 end.
 hypotheses =. 0$a:
 exhaustiveingroup =. +/2^ExhaustiveTaxa-.Outgroup
 ingroupmask =. +/2^Ingroup
 for_hypothesis. Hypotheses do.
  fields =. >hypothesis
  name =. 0{::fields
  taxa =. }.fields
  reason =. ''
  for_t. taxa do. if. -.t e.Names do. reason =. 'unknown taxon ',>t
  break. end. end.
  ids =. Names i.taxa
  if. 0=#reason do. if. Outgroup e.ids do. reason =. 'contains outgroup' end. end.
  if. #reason do. hypotheses =. hypotheses,<emit 'INVALID';name;reason
  continue. end.
  mask =. +/2^ids
  hypotheses =. hypotheses,<emit 'CLADE';name;'taxa';(#ids);'support';mask{Supports
  for_i. i.6 do.
   candidates =. (i{::SplitSets),ingroupmask
   candidates =. candidates#~mask&subset"0 candidates
   sizes =. bitcount"0 candidates
   mrca =. (sizes i.<./sizes){candidates
   intruders =. (members mrca)-.ids
   intrudertext =. '-'
   if. #intruders do. intrudertext =. ','join intruders{Names end.
   hypotheses =. hypotheses,<emit 'TEST';name;(i{::MethodNames);'monophyletic';((mrca=mask){::'no';'yes');'mrca';(bitcount mrca);'intruders';intrudertext
  end.
  subsetmask =. mask(17 b.)exhaustiveingroup
  size =. bitcount subsetmask
  if. (size<2)+.size>:bitcount exhaustiveingroup do. hypotheses =. hypotheses,<emit 'SUBSET';name;'untestable'
  else.
   with =. i.0
   without =. i.0
   for_i. i.#esplits do. if. subsetmask e.i{::esplits do. with =. with,i else. without =. without,i end. end.
   hypotheses =. hypotheses,<emit 'SUBSET';name;'taxa';size;'with';(<./with{escores);'without';(<./without{escores);'bme_with';(5 fmt <./with{ebmes);'bme_without';5 fmt <./without{ebmes
  end.
 end.
 1!:5 :: 0: <'output'
 'summary.txt'write summary
 'distances.txt'write distances
 'trees.nwk'write treefile
 'cladograms.txt'write cladograms
 'parsimony.txt'write parsimony
 'likelihood.txt'write likelihoodlines
 'bootstrap.txt'write bootstraplines
 'clock.txt'write clock
 'comparison.txt'write comparison
 'hypotheses.txt'write hypotheses
 i.0 0
)
main ''
