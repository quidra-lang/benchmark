main =: 3 : 0
  names =. ;:'January February March April May June July August September October November December'
  lengths =. 31 28 31 30 31 30 31 31 30 31 30 31
  months =. 3 2$2024 2 2026 8 2026 11
  for_index. i.3 do.
    'year month' =. index{months
    y =. year
    m =. month
    if. m<3 do.
      m =. m+12
      y =. y-1
    end.
    century =. <.y%100
    within =. 100|y
    h =. 7|1+(<.(13*(m+1))%5)+within+(<.within%4)+(<.century%4)+5*century
    weekday =. 7|h+6
    days =. (month-1){lengths
    leap =. (0=400|year)+.(0=4|year)*.0~:100|year
    if. (month=2)*.leap do. days =. 29 end.
    if. index>0 do. smoutput '' end.
    smoutput (>(month-1){names),' ',":year
    smoutput 'Su Mo Tu We Th Fr Sa'
    line =. (weekday*3)$' '
    column =. weekday
    for_day. >:i.days do.
      if. (day>1)*.column>0 do. line =. line,' ' end.
      line =. line,, '2.0' 8!:2 day
      column =. >:column
      if. (column=7)+.day=days do.
        smoutput line
        line =. ''
        column =. 0
      end.
    end.
  end.
)
main ''
