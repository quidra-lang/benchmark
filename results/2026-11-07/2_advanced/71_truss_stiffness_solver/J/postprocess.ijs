displacements =: 4 : 0
 d =. y*Prescribed
 b =. Free{x
 for_i. i.#Free do.
  w =. i{b
  for_r. Restrained do. w =. w-((<(i{Free),r){GlobalK)*r{d end.
  b =. w i}b
 end.
 (Gchol solve b)Free}d
)
forces =: 4 : 0
 ns =. NM$0.0
 for_m. i.NM do.
  'a b c d' =. m{MemberDofs
  elong =. (((c{x)-(a{x))*m{Cosines)+((d{x)-(b{x))*m{Sines
  ns =. (((m{Axial)*elong)-m{y)m}ns
 end.
 ns
)
reactions =: 4 : 0
 residual =. (GlobalK matvec x)-y
 (Restrained{residual)Restrained}(ND$0.0)
)
analyse =: 3 : 0
 Removed =: y
 assemble y
 if. Unstable>:0 do. i.0 return. end.
 result =. 0$a:
 for_l. LoadCases do.
  'fe ft p0 settle' =. y loads >l
  f =. fe+ft
  d =. f displacements settle
  ns =. d forces p0
  r =. d reactions f
  result =. result,<d;ns;r;fe
 end.
 for_combo. Combinations do.
  d =. r =. fe =. ND$0.0
  ns =. NM$0.0
  for_pair. >combo do.
   'c factor' =. pair
   rr =. c{::result
   d =. d+factor*0{::rr
   ns =. ns+factor*1{::rr
   r =. r+factor*2{::rr
   fe =. fe+factor*3{::rr
  end.
  result =. result,<d;ns;r;fe
 end.
 result
)
equilibrium =: 3 : 0
 'd ns r fe' =. y
 z =. fe+r
 for_m. i.NM do.
  ds =. m{MemberDofs
  for_j. i.4 do.
   at =. j{ds
   z =. ((at{z)-(m{ns)*(<m,j){T)at}z
  end.
 end.
 (>./|z)<:1e_6*1>.(>./|fe)>.>./|r
)
unit_result =: 3 : 0
 f =. ND$0.0
 f =. _1000 ((<y,1){Dofs)}f
 d =. f displacements 0
 (d forces NM$0.0);d reactions f
)
