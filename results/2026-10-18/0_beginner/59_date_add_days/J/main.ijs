date =: 3 : 0
  'year month day' =. y
  (_4{.'0000',":year),'-',(_2{.'0',":month),'-',_2{.'0',":day
)
main =: 3 : 0
  common =. 31 28 31 30 31 30 31 31 30 31 30 31
  for_row. 5 4$1999 12 25 10 2000 2 27 3 2021 2 20 14 2023 11 15 120 2026 10 17 1500 do.
    'year month day days' =. row
    original =. date year,month,day
    for_added. i.days do.
      leap =. (0=400|year)+.(0=4|year)*.0~:100|year
      monthlength =. (month-1){common
      if. (month=2)*.leap do. monthlength =. 29 end.
      day =. >:day
      if. day>monthlength do.
        day =. 1
        month =. >:month
        if. month>12 do. month =. 1 [ year =. >:year end.
      end.
    end.
    smoutput original,' + ',(":days),' days = ',date year,month,day
  end.
)
main ''
