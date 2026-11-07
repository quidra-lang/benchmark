main =: 3 : 0
  ranks =. 'A23456789TJQK'
  deck =. 0$<''
  for_suit. 'SHDC' do.
    for_rank. ranks do. deck =. deck,<rank,suit end.
  end.
  state =. 2026
  for_i. |.>:i.51 do.
    state =. 2147483647|48271*state
    j =. (i+1)|state
    left =. i{deck
    right =. j{deck
    deck =. right i}deck
    deck =. left j}deck
  end.
  for_start. 13*i.4 do.
    cards =. 13{.start}.deck
    smoutput }. ; (<' ') ,&.> cards
  end.
)
main ''
