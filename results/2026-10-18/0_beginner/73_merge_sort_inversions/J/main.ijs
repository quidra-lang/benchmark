mergesort =: 3 : 0
  'values left right inversions' =. y
  if. left>:right do. (values;inversions) return. end.
  middle =. <.(left+right)%2
  'values inversions' =. mergesort values;left;middle;inversions
  'values inversions' =. mergesort values;(middle+1);right;inversions
  first =. (1+middle-left){.left}.values
  second =. (right-middle){.(middle+1)}.values
  i =. j =. 0
  merged =. i.0
  while. (i<#first)*.j<#second do.
    if. (i{first)<:j{second do.
      merged =. merged,i{first
      i =. >:i
    else.
      merged =. merged,j{second
      j =. >:j
      inversions =. inversions+(#first)-i
    end.
  end.
  merged =. merged,(i}.first),j}.second
  values =. merged (left+i.#merged)}values
  smoutput 'merge [',(":left),'..',(":right),']: ',":merged
  values;inversions
)
'values inversions' =: mergesort (47 12 85 33 6 71 29 58 90 14);0;9;0
smoutput 'sorted: ',":values
smoutput 'inversions: ',":inversions
