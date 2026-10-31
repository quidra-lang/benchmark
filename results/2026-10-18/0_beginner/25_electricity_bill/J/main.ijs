main =: 3 : 0
  names =. ;:'Sato Suzuki Takahashi Tanaka Ito Watanabe'
  usages =. 85 120 254 300 438 176
  total =. 0
  for_i. i.6 do.
    usage =. i{usages
    bill =. 900 + (30*usage<.120) + (36*180<.0>.usage-120) + 40*0>.usage-300
    total =. total+bill
    smoutput (>i{names), ': ', (":usage), ' kWh, ', (":bill), ' yen'
  end.
  smoutput 'total: ', (":total), ' yen'
)
main ''
