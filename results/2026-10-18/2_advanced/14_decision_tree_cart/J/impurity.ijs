tally_labels =: 4 : 0
    result =. x$0
    for_label. y do. result =. (1+label{result) label}result end.
    result
)
class_counts =: 3 : 'ClassCount tally_labels y{Labels'
square_sum =: 3 : '+/y*y'
majority =: 3 : 'y i.>./y'
error_count =: 3 : '(+/y)->./y'
evaluation_value =: 4 : 0
    left =. +/x
    right =. +/y
    (((square_sum x)*right)+(square_sum y)*left),left*right
)
is_greater =: 4 : '((0{x)*1{y)>(0{y)*1{x'
improves =: 4 : '((0{x)*+/y)>(square_sum y)*1{x'
impurity_decrease =: 3 : 0
    'counts left right' =. y
    (((square_sum left)%+/left)+(square_sum right)%+/right)-(square_sum counts)%+/counts
)
