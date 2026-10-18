fixed =: 4 : 0
  scale =. 10 ^ x
  rounded =. (*y) * <. 0.5 + scale * |y
  , (":x) 8!:2 rounded % scale
)

values =: 48 73 56 91 35 62 84
mean =: (+/values) % #values
smoutput 2 fixed mean
