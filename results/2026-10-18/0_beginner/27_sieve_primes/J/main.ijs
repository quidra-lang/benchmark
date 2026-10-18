main =: 3 : 0
  prime =. 201$1
  prime =. 0 (0 1)}prime
  for_p. 2+i.199 do.
    if. (p{prime) *. (p*p)<:200 do.
      multiples =. (p*p) + p * i. >: <. (200-p*p)%p
      prime =. 0 multiples}prime
    end.
  end.
  primes =. I.prime
  smoutput 'count: ', ":#primes
  for_start. 10*i. >. (#primes)%10 do.
    smoutput ": (10 <. (#primes)-start) {. start}.primes
  end.
)
main ''
