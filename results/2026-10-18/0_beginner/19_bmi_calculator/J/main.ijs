fixed =: 4 : 0
  scale =. 10 ^ x
  rounded =. (*y) * <. 0.5 + scale * |y
  , (":x) 8!:2 rounded % scale
)

main =: 3 : 0
  names =. ;:'Aiko Kenji Mika Ryo Yuki'
  heights =. 158 172 165 180 150
  weights =. 45 68 70 101 52
  for_index. i.5 do.
    height =. index{heights
    bmi =. ((index{weights)*10000) % height*height
    category =. 'obese'
    if. bmi<18.5 do. category =. 'underweight'
    elseif. bmi<25 do. category =. 'normal'
    elseif. bmi<30 do. category =. 'overweight'
    end.
    smoutput (>index{names), ': BMI ', (1 fixed bmi), ' (', category, ')'
  end.
)
main ''
