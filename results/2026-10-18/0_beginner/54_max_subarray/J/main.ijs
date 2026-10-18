main =: 3 : 0
  arrays =. (3 _5 8 _2 6 _9 4 1 _7 5 _3 2);(_4 7 _1 3 _8 10 _2 5 _6 _2 9 _12 4 _1);(_6 _3 5 _1 _4 3 _9 2 3 _1 4 _5 1 6 _2)
  for_box. arrays do.
    values =. >box
    current =. best =. {.values
    start =. beststart =. bestend =. 0
    for_i. >:i.<:#values do.
      value =. i{values
      if. value>current+value do. current =. value [ start =. i
      else. current =. current+value
      end.
      if. current>best do. best =. current [ beststart =. start [ bestend =. i end.
    end.
    smoutput 'max sum ',(":best),' at [',(":beststart),', ',(":bestend),']'
  end.
)
main ''
