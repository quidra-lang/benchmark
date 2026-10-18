values =: 12 5 12 8 3 5 20 8 8 15 3 7 20 12 9
unique =: ~.values
smoutput ":unique
smoutput 'removed: ', ": (#values)-#unique
