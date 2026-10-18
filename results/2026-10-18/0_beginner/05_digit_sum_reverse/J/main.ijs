main =: 3 : 0
  for_original. 7 98000 4096 50301 2718281 123456789 do.
    remaining =. original
    digits =. 0
    total =. 0
    reversed =. 0
    while. remaining > 0 do.
      digit =. 10 | remaining
      digits =. >:digits
      total =. total + digit
      reversed =. (reversed * 10) + digit
      remaining =. <. remaining % 10
    end.
    smoutput (":original), ': digits=', (":digits), ' sum=', (":total), ' reversed=', ":reversed
  end.
)
main ''
