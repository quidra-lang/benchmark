main =: 3 : 0
  values =. 1000 900 500 400 100 90 50 40 10 9 5 4 1
  symbols =. 'M';'CM';'D';'CD';'C';'XC';'L';'XL';'X';'IX';'V';'IV';'I'
  for_number. 9 14 49 94 444 1994 2768 3999 do.
    remaining =. number
    roman =. ''
    for_i. i.13 do.
      while. remaining>:i{values do.
        roman =. roman,>i{symbols
        remaining =. remaining-i{values
      end.
    end.
    decoded =. 0
    singles =. ('IVXLCDM'i.roman){1 5 10 50 100 500 1000
    for_i. i.#singles do.
      current =. i{singles
      next =. 0
      if. (i+1)<#singles do. next =. (i+1){singles end.
      if. current<next do. decoded =. decoded-current
      else. decoded =. decoded+current
      end.
    end.
    smoutput (":number),' -> ',roman,' -> ',":decoded
  end.
)
main ''
