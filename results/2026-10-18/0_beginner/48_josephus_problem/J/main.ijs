main =: 3 : 0
  for_pair. 3 2$7 3 10 2 41 3 do.
    'n k' =. pair
    people =. >:i.n
    index =. 0
    removed =. i.0
    while. #people do.
      index =. (#people)|index+k-1
      removed =. removed,index{people
      people =. (index~:i.#people)#people
    end.
    smoutput 'n=',(":n),' k=',(":k),': ',":removed
    smoutput 'survivor: ',":{:removed
  end.
)
main ''
