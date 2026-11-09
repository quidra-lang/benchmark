main =: 3 : 0
  names =. 'ABCDEFG'
  edges =. 11 3$0 1 7 0 2 3 0 3 9 1 2 2 2 4 6 1 3 3 3 4 4 3 5 5 4 5 3 4 6 8 5 6 4
  weights =. 7 7$0
  for_edge. edges do.
    'a b weight' =. edge
    weights =. weight (<a,b)}weights
    weights =. weight (<b,a)}weights
  end.
  distance =. 0,6$_
  predecessor =. 7$_1
  done =. 7$0
  for_step. i.7 do.
    candidates =. I.-.done
    candidate_distances =. candidates{distance
    offset =. candidate_distances i. <./candidate_distances
    selected =. offset{candidates
    done =. 1 selected}done
    for_vertex. I.0<selected{weights do.
      candidate =. (selected{distance)+(<selected,vertex){weights
      if. candidate<vertex{distance do.
        distance =. candidate vertex}distance
        predecessor =. selected vertex}predecessor
      end.
    end.
  end.
  for_vertex. i.7 do.
    path =. ''
    current =. vertex
    while. current~:_1 do.
      path =. (current{names),path
      current =. current{predecessor
    end.
    joined =. }. ; (<'-') ,&.> <"0 path
    smoutput (vertex{names),': distance=',(, '0' 8!:2 vertex{distance),' path=',joined
  end.
)
main ''
