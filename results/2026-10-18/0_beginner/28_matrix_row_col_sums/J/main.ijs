matrix =: 4 5$125 340 78 912 456 603 27 819 150 384 0 765 231 498 62 947 113 586 39 720
rows =: matrix,.+/"1 matrix
columns =: +/matrix
result =: rows, columns,+/columns
smoutput '6.0' 8!:2 result
