main =: 3 : 0
  grades =. 'ABCDF'
  counts =. 5$0
  for_score. 78 90 100 59 80 85 89 70 45 93 do.
    index =. +/ score < 90 80 70 60
    counts =. (>:index{counts) index}counts
    smoutput (":score), ': ', index{grades
  end.
  for_index. i.5 do.
    smoutput (index{grades), ': ', ":index{counts
  end.
)
main ''
