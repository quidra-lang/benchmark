fraction =: 4 : '(x:x)%x:y'
lift_of =: 3 : 0
    'total count first second' =. y
    (total*count) fraction first*second
)
meets_thresholds =: 3 : 0
    'confidence lift' =. y
    (confidence>:'min_confidence' get_key Params)*.lift>:'min_lift' get_key Params
)
rule_record =: 3 : 0
    'itemset antecedent consequent count total first second' =. y
    support =. count fraction total
    confidence =. count fraction first
    lift =. lift_of total,count,first,second
    leverage =. ((total*count)-first*second) fraction total*total
    conviction =. 'INF'
    if. first~:count do. conviction =. ((total-second)*first) fraction total*(first-count) end.
    'itemset antecedent consequent count support confidence lift leverage conviction improvement rank' record (<itemset),(<antecedent),(<consequent),(<count),(<support),(<confidence),(<lift),(<leverage),(<conviction),(<0x),<0
)
sort_rules =: 3 : 0
    keys =. 0 5$a:
    for_box. y do.
        rule =. >box
        keys =. keys,1 5$(<-'confidence' get_key rule),(<-'lift' get_key rule),(<-'count' get_key rule),(<itemset_text 'antecedent' get_key rule),<itemset_text 'consequent' get_key rule
    end.
    sorted =. (/:keys){y
    for_index. i.#sorted do.
        rule =. ((<'rank'),<index+1) put_key index{::sorted
        sorted =. (<rule) index}sorted
    end.
    sorted
)
