main =: 3 : 0
  for_n. >:i.30 do.
    if. 0 = 15 | n do.
      smoutput 'FizzBuzz'
    elseif. 0 = 3 | n do.
      smoutput 'Fizz'
    elseif. 0 = 5 | n do.
      smoutput 'Buzz'
    else.
      smoutput ":n
    end.
  end.
)
main ''
