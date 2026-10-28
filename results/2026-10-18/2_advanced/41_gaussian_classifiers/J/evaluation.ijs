reduced_fraction =: 4 : 0
    if. y=0 do.
        i.0 return.
    end.
    divisor =. (|x)+.y
    (<.(x: x)%x: divisor),<.(x: y)%x: divisor
)
sum_fractions =: 3 : 0
    result =. 0 1x
    for_box. y do.
        value =. >box
        numerator =. ((0{result)*1{value)+(0{value)*1{result
        denominator =. (1{result)*1{value
        result =. numerator reduced_fraction denominator
    end.
    result
)
measures =: 3 : 0
    'actual predicted count' =. y
    matrix =. (count,count)$0
    for_index. i.#actual do.
        location =. (index{actual),index{predicted
        matrix =. (1+(<location){matrix)(<location)}matrix
    end.
    support =. +/"1 matrix
    columns =. +/matrix
    correct =. 0
    recall =. 0$a:
    precision =. 0$a:
    f1 =. 0$a:
    expected =. 0x
    macro =. 0.0
    for_index. i.count do.
        diagonal =. (<index,index){matrix
        correct =. correct+diagonal
        recall =. recall,<diagonal reduced_fraction index{support
        precision =. precision,<diagonal reduced_fraction index{columns
        f1 =. f1,<(2*diagonal)reduced_fraction (index{support)+index{columns
        expected =. expected+(index{support)*index{columns
        macro =. macro+(2.0*diagonal)%(index{support)+index{columns
    end.
    total =. sum_fractions recall
    amount =. #actual
    accuracy =. correct reduced_fraction amount
    balanced =. (0{total)reduced_fraction count*1{total
    kappa =. ((amount*correct)-expected)reduced_fraction (amount*amount)-expected
    (<matrix),(<support),(<correct),(<accuracy),(<balanced),(<kappa),(<recall),(<precision),(<f1),<macro%count
)
m_matrix =: 0&{::
m_support =: 1&{::
m_correct =: 2&{::
m_accuracy =: 3&{::
m_balanced =: 4&{::
m_kappa =: 5&{::
m_recall =: 6&{::
m_precision =: 7&{::
m_f1 =: 8&{::
m_macro =: 9&{::
mcnemar =: 3 : 0
    'actual first second' =. y
    correct_first =. actual=first
    correct_second =. actual=second
    b01 =. +/correct_first*.-.correct_second
    b10 =. +/correct_second*.-.correct_first
    chi =. 0.0
    if. b01~:b10 do.
        difference =. (|b01-b10)-1
        chi =. (0.0+difference*difference)%b01+b10
    end.
    b01,b10,chi,chi>3.841
)
random_draw =: 3 : '2147483647|48271x*y'
