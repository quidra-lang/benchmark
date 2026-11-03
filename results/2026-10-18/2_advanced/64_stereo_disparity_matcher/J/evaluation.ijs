ratio =: 4 : 0
 if. y=0 do. '0/1 0.00' return. end.
 g =. x+.y
 (str x%g),'/',(str y%g),' ',(100x*x)two y
)
truth_regions =: 3 : 0
 Known =: G>0
 Occ =: N$0
 Disc =: N$0
 for_p. I.Known do.
  'xx yy' =. xy p
  g =. p{G
  oc =. xx<g
  for_x2. i.W do.
   gg =. (index x2,yy){G
   if. (gg>g)*.(x2-gg)=xx-g do. oc =. 1 end.
  end.
  Occ =: oc p}Occ
 end.
 Nonocc =: Known*.-.Occ
 for_p. I.Nonocc do.
  ns =. Directions neighbours p
  Disc =: (+./(ns{Known)*.2<:|(ns{G)-p{G)p}Disc
 end.
 Regions =: Nonocc;Known;Disc
 Layers =: /:~~.Known#G
 i.0 0
)
evaluate =: 4 : 0
 ids =. I.x
 values =. ids{y
 gt =. ids{G
 valid =. values>0
 err =. |values-gt
 (#ids),(+/valid),(+/(-.valid)+.err>1),(+/(-.valid)+.err>2),(+/valid#err),+/valid*.err=0
)
region_line =: 3 : 0
 'name mask image' =. y
 'n v b1 b2 s ex' =. mask evaluate image
 mae =. '-'
 if. v do. mae =. s two v end.
 emit 'region';name;'pixels';n;'valid';v;'bad1';(b1 ratio n);'bad2';(b2 ratio n);'mae';mae;'exact';ex
)
