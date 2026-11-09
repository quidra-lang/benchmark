words =: ;:'we planted beans and carrots in the garden behind our old house'
lengths =: #&>words
smoutput 'words: ', ":#words
smoutput 'longest: ', >(lengths i. >./lengths){words
smoutput 'shortest: ', >(lengths i. <./lengths){words
total =: +/lengths
smoutput 'average length: ', , '2' 8!:2 total%#words
