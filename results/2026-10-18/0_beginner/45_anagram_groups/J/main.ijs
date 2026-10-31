main =: 3 : 0
  words =. ;:'listen stone night silent notes apple thing enlist earth onset heart tones'
  signatures =. /:~&.>words
  used =. (#words)$0
  for_i. i.#words do.
    if. i{used do. continue. end.
    mask =. (i{signatures)-:&>signatures
    smoutput }. ; (<' ') ,&.> mask#words
    used =. used+.mask
  end.
)
main ''
