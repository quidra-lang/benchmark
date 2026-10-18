fixed =: 4 : 0
  scale =. 10 ^ x
  rounded =. (*y) * <. 0.5 + scale * |y
  , (":x) 8!:2 rounded % scale
)

main =: 3 : 0
  for_row. 6 3$1 _3 _10 _2 5 4 3 1 _2 4 _12 9 1 2 5 _2 3 _4 do.
    'a b c' =. row
    d =. (b*b)-4*a*c
    denominator =. 2.0*a
    prefix =. ":row
    prefix =. '-' (I.prefix='_')}prefix
    prefix =. prefix,': '
    if. d>0 do.
      root =. %:0.0+d
      first =. ((-b)+root)%denominator
      second =. ((-b)-root)%denominator
      smoutput prefix,'x1 = ',(4 fixed first>.second),', x2 = ',4 fixed first<.second
    elseif. d=0 do.
      smoutput prefix,'x = ',4 fixed (-b)%denominator
    else.
      p =. (-b)%denominator
      imaginary =. (%:-d) % 2.0*|a
      realtext =. 4 fixed p
      imaginarytext =. 4 fixed imaginary
      smoutput prefix,'x = ',realtext,' + ',imaginarytext,'i, ',realtext,' - ',imaginarytext,'i'
    end.
  end.
)
main ''
