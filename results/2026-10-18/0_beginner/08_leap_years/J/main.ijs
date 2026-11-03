main =: 3 : 0
  for_year. 1900 1988 2000 2019 2024 2026 2032 2100 do.
    leap =. (0 = 400 | year) +. (0 = 4 | year) *. 0 ~: 100 | year
    result =. 'common year'
    if. leap do.
      result =. 'leap year'
    end.
    smoutput (":year), ': ', result
  end.
)
main ''
