main =: 3 : 0
  polygon =. 8 2$1 1 11 2 13 9 9 7 7 12 5 6 2 10 3 5
  for_point. 6 2$4 8 6 4 10 8 7 11 14 3 12 8 do.
    'px py' =. point
    crossings =. 0
    for_i. i.8 do.
      j =. 8|i+1
      'x1 y1' =. i{polygon
      'x2 y2' =. j{polygon
      if. (y1>py)~:y2>py do.
        intersection =. x1 + ((x2-x1)*(py-y1)) % y2-y1
        if. intersection>px do. crossings =. >:crossings end.
      end.
    end.
    result =. 'outside'
    if. 1=2|crossings do. result =. 'inside' end.
    smoutput '(',(":px),', ',(":py),'): ',result
  end.
)
main ''
