main =: 3 : 0
  for_original. 8 3$3 8 5 6 6 6 5 8 5 13 5 12 2 9 4 7 4 7 8 6 7 4 9 6 do.
    'a b c' =. /:~original
    result =. 'not a triangle'
    if. (a+b)>c do.
      side =. 'scalene'
      if. a=c do. side =. 'equilateral'
      elseif. (a=b)+.b=c do. side =. 'isosceles'
      end.
      angle =. 'obtuse'
      if. (c*c)<(a*a)+b*b do. angle =. 'acute'
      elseif. (c*c)=(a*a)+b*b do. angle =. 'right'
      end.
      result =. side,' ',angle
    end.
    smoutput (":original),': ',result
  end.
)
main ''
