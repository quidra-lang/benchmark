fixed =: 4 : 0
  scale =. 10 ^ x
  rounded =. (*y) * <. 0.5 + scale * |y
  , (":x) 8!:2 rounded % scale
)

main =: 3 : 0
  polygons =. (4 2$0 0 5 0 6 4 1 3);(5 2$2 1 0 4 3 7 7 6 8 2);(7 2$0 0 8 0 8 6 5 6 4 3 3 6 0 6)
  for_k. i.3 do.
    polygon =. >k{polygons
    crosssum =. 0
    perimeter =. 0.0
    for_i. i.#polygon do.
      j =. (#polygon)|i+1
      'x1 y1' =. i{polygon
      'x2 y2' =. j{polygon
      crosssum =. crosssum+(x1*y2)-x2*y1
      dx =. x1-x2
      dy =. y1-y2
      edge =. %:0.0+(dx*dx)+dy*dy
      perimeter =. perimeter+edge
    end.
    area =. (|crosssum)%2
    smoutput 'polygon ',(":>:k),': area=',(1 fixed area),' perimeter=',3 fixed perimeter
  end.
)
main ''
