main =: 3 : 0
  sentence =. tolower 'Peter Piper picked a peck of pickled peppers!'
  for_letter. 'abcdefghijklmnopqrstuvwxyz' do.
    count =. +/letter=sentence
    if. count>0 do. smoutput letter, ': ', ":count end.
  end.
)
main ''
