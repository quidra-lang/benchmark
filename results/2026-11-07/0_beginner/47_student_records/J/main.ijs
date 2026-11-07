main =: 3 : 0
  names =. ;:'Tanaka Suzuki Yamada Ito Kato Mori'
  scores =. 6 3$78 85 94 88 74 82 65 90 71 80 79 85 92 88 95 70 62 78
  students =. names,.<"0 +/"1 scores
  totals =. >1{"1 students
  alpha =. /:names
  order =. alpha {~ \:alpha{totals
  previous =. _1
  rank =. 0
  for_position. i.6 do.
    i =. position{order
    student =. i{students
    total =. >1{student
    if. total~:previous do. rank =. >:position end.
    previous =. total
    smoutput (":rank),'. ',(>0{student),' total=',(":total),' average=',, '2' 8!:2 total%3
  end.
)
main ''
