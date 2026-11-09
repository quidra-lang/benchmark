pcr =: 4 : '(((3.141592653589793*3.141592653589793)*(x{E))*y)%*:(x{Lengths)'
utilization =: 3 : 0
 'm axial area moment' =. y
 ((|axial%area)%(m{Fy))>.(0>.-axial)%(m pcr moment)
)
slenderness =: 3 : 0
 'm area moment' =. y
 (m{Lengths)%%:moment%area
)
limits =: 3 : 0
 'lc lt' =. num&>pv 'slenderness'
 answer =. NM$lt
 for_r. NC}.y do. answer =. lc(I.(1{::>r)<0)}answer end.
 answer
)
choose_sections =: 3 : 0
 'results lim' =. y
 selected =. i.0
 for_g. i.#GroupNames do.
  members =. I.Group=g
  choice =. (#Sections)-1
  for_s. i.#Sections do.
   'a moment' =. s{Sections
   ok =. 1
   for_m. members do.
    if. (slenderness m;a;moment)>m{lim do. ok =. 0
    break. end.
    for_r. NC}.results do.
     if. (utilization m;(m{1{::>r);a;moment)>1 do. ok =. 0
     break. end.
    end.
    if. -.ok do. break. end.
   end.
   if. ok do. choice =. s
   break. end.
  end.
  selected =. selected,choice
 end.
 selected
)
