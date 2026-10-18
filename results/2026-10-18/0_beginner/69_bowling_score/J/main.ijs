main =: 3 : 0
  games =. (8 1 10 7 3 9 0 10 10 2 6 6 4 0 9 10 7 2);(3 4 5 2 7 1 0 6 8 1 4 4 2 3 6 2 9 0 1 5);(5 5 0 10 7 3 9 1 6 4 8 2 3 7 4 6 1 9 7 3 5);(12$10);(10 9 1 10 10 7 2 0 0 10 8 1 10 6 4 10)
  for_game. i.5 do.
    rolls =. >game{games
    index =. total =. 0
    cumulative =. i.0
    for_frame. i.10 do.
      if. frame=9 do. total =. total + +/ index }. rolls
      elseif. 10=index{rolls do.
        total =. total+10+((index+1){rolls)+(index+2){rolls
        index =. >:index
      else.
        pins =. (index{rolls)+(index+1){rolls
        total =. total+pins
        if. pins=10 do. total =. total+(index+2){rolls end.
        index =. index+2
      end.
      cumulative =. cumulative,total
    end.
    smoutput 'game ',(":>:game),': ',":cumulative
  end.
)
main ''
