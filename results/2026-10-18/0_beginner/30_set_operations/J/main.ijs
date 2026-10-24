a =: ~.12 5 8 21 5 17 3 12 9
b =: ~.8 14 21 6 14 3 25 6
smoutput 'union: ', ":/:~ ~.a,b
smoutput 'intersection: ', ":/:~ a #~ a e. b
smoutput 'difference: ', ":/:~ a -. b
smoutput 'symmetric difference: ', ":/:~ (a-.b),b-.a
