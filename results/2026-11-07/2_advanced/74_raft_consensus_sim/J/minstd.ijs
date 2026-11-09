random =: 3 : 0
 RNG =: 2147483647|48271x*RNG
 Draws =: Draws+1
 RNG
)
set_timer =: 3 : 0
 d =. Emin+(1+Emax-Emin)|random ''
 Deadline =: (Now+d)y}Deadline
 i.0 0
)
