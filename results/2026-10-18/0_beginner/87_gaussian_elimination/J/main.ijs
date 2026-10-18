fixed =: 4 : 0
  scale =. 10 ^ x
  rounded =. (*y) * <. 0.5 + scale * |y
  , (":x) 8!:2 rounded % scale
)

main =: 3 : 0
  systems =. (3 4$2 _1 3 7 4 1 _2 3 _3 5 1 _4);(4 5$1 3 _2 4 6 5 _2 1 3 _7 _2 4 6 _1 9 3 1 _4 2 5)
  for_system. i.2 do.
    a =. 0.0+>system{systems
    n =. #a
    for_k. i.n do.
      pivot =. k
      for_i. (k+1) + i. n-(k+1) do.
        if. (|(<i,k){a)>|(<pivot,k){a do. pivot =. i end.
      end.
      if. pivot~:k do.
        first =. k{a
        a =. (pivot{a) k}a
        a =. first pivot}a
      end.
      for_i. (k+1) + i. n-(k+1) do.
        factor =. ((<i,k){a)%(<k,k){a
        for_j. k+i.(n+1)-k do.
          value =. ((<i,j){a)-factor*(<k,j){a
          a =. value (<i,j)}a
        end.
      end.
    end.
    solution =. n$0.0
    for_i. |.i.n do.
      sum =. (<i,n){a
      for_j. (i+1) + i. n-(i+1) do.
        sum =. sum-((<i,j){a)*j{solution
      end.
      solution =. (sum%(<i,i){a) i}solution
    end.
    smoutput 'system ',(":>:system),':'
    for_i. i.n do. smoutput 'x',(":>:i),' = ',4 fixed i{solution end.
  end.
)
main ''
