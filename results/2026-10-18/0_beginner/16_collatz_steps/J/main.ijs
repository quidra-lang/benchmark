main =: 3 : 0
  for_start. 1 6 27 97 871 do.
    n =. start
    steps =. 0
    largest =. n
    while. n ~: 1 do.
      if. 0 = 2|n do.
        n =. <.n%2
      else.
        n =. 1+3*n
      end.
      steps =. >:steps
      largest =. largest>.n
    end.
    smoutput (":start), ': steps=', (":steps), ' max=', ":largest
  end.
)
main ''
