fixed =: 4 : 0
  scale =. 10 ^ x
  rounded =. (*y) * <. 0.5 + scale * |y
  , (":x) 8!:2 rounded % scale
)

words =: ;:'we planted beans and carrots in the garden behind our old house'
lengths =: #&>words
smoutput 'words: ', ":#words
smoutput 'longest: ', >(lengths i. >./lengths){words
smoutput 'shortest: ', >(lengths i. <./lengths){words
smoutput 'average length: ', 2 fixed (+/lengths)%#words
