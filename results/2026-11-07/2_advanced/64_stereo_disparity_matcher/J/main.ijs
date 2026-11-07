ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'pgm_io.ijs'
load SourceDirectory,'costs.ijs'
load SourceDirectory,'aggregation.ijs'
load SourceDirectory,'refinement.ijs'
load SourceDirectory,'evaluation.ijs'
select_disparity =: 3 : 0
 right =. N$_1
 for_p. i.N do.
  'xx yy' =. xy p
  best =. _
  for_j. i.#Ds do.
   d =. j{Ds
   if. xx+d<W do.
    c =. (<(index (xx+d),yy),j){y
    if. c<best do. best =. c
    right =. d p}right end.
   end.
  end.
 end.
 image =. N$0
 reasons =. N$0
 margins =. N$0x
 lr =. 4$0
 bounds =. 0
 for_p. i.N do.
  'xx yy' =. xy p
  costs =. p{y
  j =. costs i.<./costs
  d =. j{Ds
  c1 =. j{costs
  c2 =. <./((2<:|Ds-d)#costs)
  bounds =. bounds+((d=Dmin)+.d=Dmax)
  consistent =. (#Ds)$0
  for_e. i.#Ds do.
   v =. e{Ds
   if. xx>:v do. consistent =. ((pn 'lr_max_diff')>:|v-(index (xx-v),yy){right)e}consistent end.
  end.
  code =. 0
  if. (p{Texture)<pn 'texture_threshold' do. code =. 50
  elseif. (100*c2)<:(100+pn 'uniqueness')*c1 do. code =. 100
  elseif. xx<d do. code =. 150
  elseif. -.j{consistent do. code =. (+./consistent){255 200 end.
  reasons =. code p}reasons
  if. code=0 do. image =. d p}image
  margins =. (c2-c1)p}margins end.
  if. code e.0 200 255 do.
   diff =. 3<.|d-(index (xx-d),yy){right
   lr =. (1+diff{lr)diff}lr
  end.
 end.
 image;reasons;margins;lr;bounds
)
components =: 4 : 0
 seen =. N$0
 groups =. 0$a:
 for_start. I.y>0 do.
  if. start{seen do. continue. end.
  queue =. ,start
  seen =. 1 start}seen
  head =. 0
  while. head<#queue do.
   p =. head{queue
   head =. head+1
   for_q. (4{.Directions)neighbours p do.
    if. (-.q{seen)*.(q{y)>0 do.
     if. x>:|(p{y)-q{y do. queue =. queue,q
     seen =. 1 q}seen end.
    end.
   end.
  end.
  groups =. groups,<queue
 end.
 groups
)
postprocess =: 3 : 0
 'a0 reasons margins lr bounds' =. y
 a1 =. a0
 nc =. np =. 0
 for_c. (pn 'speckle_range')components a0 do.
  ids =. >c
  if. (#ids)<pn 'speckle_size' do. a1 =. 0 ids}a1
  nc =. nc+1
  np =. np+#ids end.
 end.
 a2 =. a1
 for_p. I.a1>0 do.
  ns =. p,Directions neighbours p
  values =. ns{a1
  a2 =. (lower_median values#~values>0)p}a2
 end.
 a3 =. a2
 sources =. N$4
 for_p. i.N do.
  if. p{a2 do. sources =. ((p{a2)~:p{a0)p}sources
  else.
   dirs =. Directions
   back =. (p{reasons)e.150 255
   if. back do. dirs =. 2{.Directions end.
   values =. i.0
   for_r. dirs do.
    q =. (xy p)+r
    while. inside q do.
     v =. (index q){a2
     if. v>0 do. values =. values,v
     break. end.
     q =. q+r
    end.
   end.
   if. #values do.
    if. back do. v =. <./values else. v =. lower_median values end.
    a3 =. v p}a3
    sources =. (back{3 2)p}sources
   end.
  end.
 end.
 summary =. nc,np,(+/a2~:a1),(+/sources=2),(+/sources=3),+/sources=4
 a3;sources;summary
)
method_report =: 3 : 0
 'name image metadata kind' =. y
 valid =. image>0
 values =. valid#image
 lines =. <emit 'method';name;'valid';(+/valid);'invalid';N-+/valid
 if. #values do. lines =. lines,<emit 'disparity min';(<./values);'max';(>./values);'median';(lower_median values);'distinct';#~.values
 else. lines =. lines,<'disparity min - max - median - distinct 0' end.
 jumps =. 2$0
 for_p. i.N do.
  for_d. i.2 do.
   qxy =. (xy p)+d{1 0,:0 1
   if. inside qxy do.
    q =. index qxy
    if. (p{valid)*.q{valid do. jumps =. ((d{jumps)+2<:|(p{image)-q{image)d}jumps end.
   end.
  end.
 end.
 lines =. lines,<emit 'jumps horizontal';(0{jumps);'vertical';1{jumps
 if. kind=0 do.
  'sel window' =. metadata
  'a reasons margins lr bounds' =. sel
  lines =. lines,<emit 'window';window;'bounds';bounds
  lines =. lines,<emit 'reasons textureless';(+/reasons=50);'nonunique';(+/reasons=100);'outside';(+/reasons=150);'mismatch';(+/reasons=200);'occluded';+/reasons=255
  lines =. lines,<emit 'lr 0';(0{lr);'1';(1{lr);'2';(2{lr);'3+';3{lr
 elseif. kind=1 do.
  lines =. lines,<emit 'votes 0';(+/Votes=0);'1';(+/Votes=1);'2';(+/Votes=2);'3';(+/Votes=3);'4';+/Votes=4
 else.
  'a sources summary' =. metadata
  'nc np nm nb ni nn' =. summary
  lines =. lines,<emit 'postprocess speckles';nc;np;'median';nm;'background';nb;'interpolated';ni;'unfilled';nn
  for_i. i.5 do.
   stats =. (Known*.sources=i)evaluate image
   lines =. lines,<emit 'source';(i{::SourceNames);'pixels';(0{stats);'bad1';(2{stats)ratio 0{stats
  end.
 end.
 for_r. i.3 do. lines =. lines,<region_line (r{::RegionNames);(r{::Regions);image end.
 ids =. I.Nonocc*.valid
 if. #ids do.
  v =. ids{image
  gt =. ids{G
  fb =. (pn 'focal_length')*pn 'baseline'
  errors =. |(<.((200x*fb)+v)%(2*v))-<.((200x*fb)+gt)%(2*gt)
  lines =. lines,<emit 'depth_error pixels';(#ids);'mean';((+/errors)two 100*#ids);'max';(>./errors)two 100
 else. lines =. lines,<'depth_error pixels 0 mean - max -' end.
 errors =. |image-G
 counts =. i.0
 for_e. i.4 do. counts =. counts,+/Known*.valid*.errors=e end.
 counts =. counts,(+/Known*.valid*.errors>:4),+/Known*.-.valid
 lines,<emit 'errors 0';(0{counts);'1';(1{counts);'2';(2{counts);'3';(3{counts);'4+';(4{counts);'invalid';5{counts
)
object_report =: 3 : 0
 objects =. 0$a:
 keys =. 0 3$0
 small =. 0
 for_c. (pn 'object_range')components y do.
  ids =. >c
  if. (#ids)<pn 'object_min_size' do. small =. small+1
  continue. end.
  objects =. objects,<ids
  keys =. keys,(-lower_median ids{y),(-#ids),{.ids
 end.
 objects =. (/:keys){objects
 lines =. <emit 'objects';(#objects);'small';small;'pixels';+/#&>objects
 detected =. i.0
 for_i. i.#objects do.
  ids =. i{::objects
  values =. ids{y
  coords =. xy"0 ids
  'x0 y0' =. <./coords
  'x1 y1' =. >./coords
  dm =. lower_median values
  truth =. (ids{Known)#ids{G
  suffix =. 'truth - iou -'
  if. #truth do.
   ts =. /:~~.truth
   counts =. +/"1 ts=/truth
   t =. (counts i.>./counts){ts
   h =. +/truth=t
   union =. (#ids)+(+/G=t)-h
   suffix =. emit 'truth';t;'iou';h ratio union
   if. (2*h)>union do. detected =. detected,t end.
  end.
  lines =. lines,<emit 'object';(i+1);'pixels';(#ids);'box';x0;y0;x1;y1;'disparity';(<./values);(>./values);'median';dm;'mean';((+/values)two #ids);'depth';(((pn 'focal_length')*(pn 'baseline')*#ids)two +/values);'size';(((1+x1-x0)*pn 'baseline')two dm);(((1+y1-y0)*pn 'baseline')two dm);suffix
 end.
 missed =. Layers-.detected
 t =. '-'
 if. #missed do. t =. emit <"0 missed end.
 lines,<emit 'layers';(#Layers);'detected';(#~.detected);'missed';t
)
main =: 3 : 0
 read_input ''
 1!:5 :: 0: <'output'
 SourceNames =: 'kept';'median';'background';'interpolated';'none'
 MethodNames =: 'sad';'ssd';'census';'sgm';'fusion';'wta_final';'sgm_final'
 RegionNames =: 'nonocc';'all';'disc'
 CL =: census IL
 CR =: census IR
 Texture =: texture ''
 truth_regions ''
 selections =. images =. windows =. 0$a:
 sweeps =. 0$a:
 for_kind. 3{.MethodNames do.
  kind =. >kind
  best =. _ _
  for_w. num&>pv kind,'_windows' do.
   sel =. select_disparity cost_volume kind;w
   im =. 0{::sel
   stats =. Nonocc evaluate im
   sweeps =. sweeps,<emit 'sweep';kind;'window';w;'valid';(+/im>0);'bad1';((2{stats)ratio 0{stats);'bad2';(3{stats)ratio 0{stats
   key =. 2 3{stats
   choose =. ((0{key)<0{best)+.((0{key)=0{best)*.(1{key)<1{best
   if. choose do. best =. key
   selected =. sel
   chosenw =. w end.
  end.
  selections =. selections,<selected
  images =. images,<0{::selected
  windows =. windows,<chosenw
 end.
 stages =. aggregate cost_volume (0{::pv 'sgm_cost');pn 'sgm_window'
 paths =. 0$a:
 for_i. i.#stages do.
  sel =. select_disparity i{::stages
  stats =. Nonocc evaluate 0{::sel
  paths =. paths,<emit 'paths';(i+1);'valid';(+/(0{::sel)>0);'bad1';((2{stats)ratio 0{stats);'bad2';(3{stats)ratio 0{stats
 end.
 S =: >{:stages
 selections =. selections,<sel
 windows =. windows,<pn 'sgm_window'
 images =. images,<0{::sel
 Votes =: N$0
 fusion =. N$0
 for_p. i.N do.
  v =. p&{&>images
  v =. v#~v>0
  Votes =: (#v)p}Votes
  if. #v do.
   m =. lower_median v
   if. (+/1>:|v-m)>:pn 'fusion_min_votes' do. fusion =. m p}fusion end.
  end.
 end.
 images =. images,<fusion
 wi =. MethodNames i.<0{::pv 'wta_cost'
 pw =. postprocess wi{::selections
 ps =. postprocess 3{::selections
 images =. images,(<0{::pw),<0{::ps
 'disparity_wta.pgm'write_pgm 8*5{::images
 'disparity_sgm.pgm'write_pgm 8*6{::images
 'occlusion.pgm'write_pgm 1{::3{::selections
 final =. 6{::images
 errorimage =. N$0
 for_p. I.Known do.
  v =. 255
  if. p{final do. v =. 50*(1+3<.|(p{final)-p{G) end.
  errorimage =. v p}errorimage
 end.
 'error_sgm.pgm'write_pgm errorimage
 depth =. <'x,y,sad,ssd,census,sgm,disparity,source,subpixel,depth,truth,truth_depth'
 for_sample. Samples do.
  p =. index sample
  f =. <"0 sample
  for_im. 4{.images do.
   v =. p{>im
   t =. '-'
   if. v do. t =. str v end.
   f =. f,<t
  end.
  d =. p{final
  if. d do. f =. f,(<str d),(<(p{1{::ps){::SourceNames),S subpixel p,d
  else. f =. f,'-';'none';'-';'-' end.
  g =. p{G
  if. g do. f =. f,(<str g),<((pn 'focal_length')*pn 'baseline')two g
  else. f =. f,'-';'-' end.
  depth =. depth,<','join f
 end.
 'depth.csv'write_lines depth
 lines =. (<emit 'image';W;H),<emit 'disparities';Dmin;Dmax
 for_item. (<'left';IL),<('right';IR) do.
  'name im' =. >item
  lines =. lines,<emit name;'mean';((+/im)two N);'min';(<./im);'max';>./im
 end.
 lines =. lines,<emit 'texture mean';((+/Texture)two N);'textureless';+/Texture<pn 'texture_threshold'
 lines =. lines,<emit 'ground_truth known';(+/Known);'nonocc';(+/Nonocc);'occluded';(+/Occ);'disc';(+/Disc);'unknown';N-+/Known
 delta =. i.0
 for_p. I.Nonocc do.
  'xx yy' =. xy p
  delta =. delta,((index (xx-p{G),yy){IR)-p{IL
 end.
 lines =. lines,<emit 'photometric pixels';(#delta);'mean_abs';((+/|delta)two #delta);'bias';(+/delta)signed_two #delta
 lines =. lines,sweeps,paths
 for_i. i.7 do.
  kind =. 0
  if. i<4 do. metadata =. (i{::selections);i{::windows
  elseif. i=4 do. kind =. 1
  metadata =. i.0
  elseif. i=5 do. kind =. 2
  metadata =. pw
  else. kind =. 2
  metadata =. ps end.
  lines =. lines,method_report (i{::MethodNames);(i{::images);metadata;kind
 end.
 for_r. i.3 do.
  keys =. 0 4$0x
  for_i. i.7 do.
   'n v b1 b2 s ex' =. (r{::Regions)evaluate i{::images
   avg =. _
   if. v do. avg =. (x:s)%x:v end.
   keys =. keys,b1,b2,avg,i
  end.
  lines =. lines,<emit 'ranking';(r{::RegionNames);' 'join (/:keys){MethodNames
 end.
 for_i. i.4 do.
  'im reasons margins lr bounds' =. i{::selections
  detected =. reasons e.150 255
  tp =. +/Occ*.detected
  fp =. +/Nonocc*.detected
  fn =. +/Occ*.-.detected
  name =. i{::MethodNames
  lines =. lines,<emit 'occlusion';name;'tp';tp;'fp';fp;'fn';fn;'precision';(tp ratio tp+fp);'recall';tp ratio tp+fn
 end.
 for_i. i.4 do.
  'im reasons margins lr bounds' =. i{::selections
  ids =. I.Nonocc*.im>0
  ids =. (\:ids{margins){ids
  for_percent. 25 50 75 100 do.
   n =. <.(99+(#ids)*percent)%100
   subset =. n{.ids
   margin =. '-'
   if. n do. margin =. str ({:subset){margins end.
   bad =. +/1<.|(subset{im)-subset{G
   lines =. lines,<emit 'confidence';(i{::MethodNames);percent;'pixels';n;'margin';margin;'bad1';bad ratio n
  end.
 end.
 for_g. Layers do.
  bad =. i.0
  for_im. images do. bad =. bad,2{(Nonocc*.G=g)evaluate >im end.
  lines =. lines,<emit 'layer';g;'pixels';(+/G=g);'nonocc';(+/Nonocc*.G=g);'bad1';emit <"0 bad
 end.
 for_d. Ds do. lines =. lines,<emit 'histogram';d;+/final=d end.
 'evaluation.txt'write_lines lines
 'objects.txt'write_lines object_report final
 i.0 0
)
main ''
