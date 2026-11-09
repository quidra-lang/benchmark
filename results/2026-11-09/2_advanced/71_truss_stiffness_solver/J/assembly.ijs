properties =: 3 : 0
 Lengths =: Cosines =: Sines =: i.0
 Adjacent =: (NN,NN)$0
 for_m. i.NM do.
  i =. m{Mi
  j =. m{Mj
  'dx dy' =. (j{Coordinates)-i{Coordinates
  l =. %:(dx*dx)+dy*dy
  Lengths =: Lengths,l
  Cosines =: Cosines,dx%l
  Sines =: Sines,dy%l
  Adjacent =: 1(<i,j)}Adjacent
  Adjacent =: 1(<j,i)}Adjacent
 end.
 Degrees =: +/"1 Adjacent
 q =. ,{./:Degrees
 head =. 0
 while. head<#q do.
  ns =. (I.(head{q){Adjacent)-.q
  ns =. (/:((ns{Degrees),.ns)){ns
  q =. q,ns
  head =. head+1
 end.
 Renumbering =: |.q
 NewNumber =: Renumbering i.i.NN
 Dofs =: (2*NewNumber)+/0 1
 ND =: 2*NN
 Fixed =: ND$0
 Prescribed =: ND$0.0
 for_s. Supports do.
  node =. 0{s
  ds =. node{Dofs
  for_j. i.2 do.
   if. (j+1){s do.
    Fixed =: 1(j{ds)}Fixed
    Prescribed =: ((j+3){s)(j{ds)}Prescribed
   end.
  end.
 end.
 Restrained =: I.Fixed
 Free =: I.-.Fixed
 MemberDofs =: (Mi{Dofs),.Mj{Dofs
 T =: (-Cosines),.(-Sines),.Cosines,.Sines
 E =: 0{"1 Material{Materials
 Fy =: 1{"1 Material{Materials
 Rho =: 2{"1 Material{Materials
 Expansion =: 3{"1 Material{Materials
 i.0 0
)
assemble =: 3 : 0
 Areas =: 0{"1 CurrentSections{Sections
 Moments =: 1{"1 CurrentSections{Sections
 Axial =: (E*Areas)%Lengths
 Weights =: (((Rho*9.81)*Areas)*Lengths)%1000000000
 GlobalK =: (ND,ND)$0.0
 for_m. (i.NM)-.y do.
  ds =. m{MemberDofs
  km =. (m{Axial)*(m{T)*/m{T
  for_i. i.4 do.
   for_j. i.4 do.
    at =. (i{ds),j{ds
    GlobalK =: (((<at){GlobalK)+(<i,j){km)(<at)}GlobalK
   end.
  end.
 end.
 Kff =: (<Free;Free){GlobalK
 'Unstable Gchol' =: cholesky Kff
 i.0 0
)
loads =: 4 : 0
 removed =. x
 fe =. ft =. ND$0.0
 p0 =. NM$0.0
 settle =. 0
 for_l. y do.
  f =. >l
  select. 0{::f
  case. 'FORCE' do.
   node =. NodeIds i.num 1{::f
   for_j. i.2 do. d =. (<node,j){Dofs
   fe =. ((d{fe)+1000*num (j+2){::f)d}fe end.
  case. 'TEMPERATURE' do.
   m =. MemberIds i.num 1{::f
   if. m=removed do. continue. end.
   pp =. ((m{E)*(m{Areas)*(m{Expansion))*num 2{::f
   p0 =. pp m}p0
   ds =. m{MemberDofs
   for_j. i.4 do. d =. j{ds
   ft =. ((d{ft)+pp*(<m,j){T)d}ft end.
  case. 'SELFWEIGHT' do.
   for_m. (i.NM)-.removed do.
    for_node. (m{Mi),m{Mj do.
     d =. (<node,1){Dofs
     fe =. ((d{fe)-(m{Weights)%2)d}fe
    end.
   end.
  case. 'SETTLEMENT' do. settle =. 1
  end.
 end.
 fe;ft;p0;settle
)
