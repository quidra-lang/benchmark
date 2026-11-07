main =: 3 : 0
  coins =. 1 5 6 9
  for_target. 8 11 15 22 33 40 do.
    minimum =. (target+1)$target+1
    minimum =. 0 (0)}minimum
    for_amount. >:i.target do.
      for_coin. coins do.
        if. coin<:amount do.
          value =. (amount{minimum)<.1+(amount-coin){minimum
          minimum =. value amount}minimum
        end.
      end.
    end.
    ways =. (target+1)$0
    ways =. 1 (0)}ways
    for_coin. coins do.
      for_amount. coin+i.(target-coin)+1 do.
        ways =. ((amount{ways)+(amount-coin){ways) amount}ways
      end.
    end.
    remaining =. target
    greedy =. 0
    for_coin. |.coins do.
      greedy =. greedy+<.remaining%coin
      remaining =. coin|remaining
    end.
    smoutput (":target),': min=',(":target{minimum),' greedy=',(":greedy),' ways=',":target{ways
  end.
)
main ''
