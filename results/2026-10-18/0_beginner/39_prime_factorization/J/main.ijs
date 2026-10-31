main =: 3 : 0
  for_original. 84 9973 15625 1001 123456 48000 999958 999999 do.
    remaining =. original
    divisor =. 2
    factors =. 0$<''
    while. (divisor*divisor)<:remaining do.
      exponent =. 0
      while. 0=divisor|remaining do.
        remaining =. <.remaining%divisor
        exponent =. >:exponent
      end.
      if. exponent>0 do.
        factor =. ":divisor
        if. exponent>:2 do. factor =. factor,'^',":exponent end.
        factors =. factors,<factor
      end.
      divisor =. >:divisor
    end.
    if. remaining>1 do. factors =. factors,<":remaining end.
    joined =. 3}.; (<' * ') ,&.> factors
    smoutput (":original),' = ',joined
  end.
)
main ''
