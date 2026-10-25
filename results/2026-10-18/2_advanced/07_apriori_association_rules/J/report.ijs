itemset_text =: 3 : '''+'' join y'
split_itemset_text =: 3 : 0
    if. #y do. '+' split y else. 0$a: end.
)
fraction_text =: 3 : 0
    'numerator denominator' =. _1 x:2 x:|y
    scaled =. (10000*numerator) div denominator
    decimal =. (number scaled div 10000),'.',_4{.'0000',number 10000|scaled
    sign =. ''
    if. y<0 do.
        sign =. '-'
        if. scaled>0 do. decimal =. '-',decimal end.
    end.
    sign,(number numerator),'/',(number denominator),'=',decimal
)
percent_text =: 4 : 0
    scaled =. (10000*x) div y
    (number scaled div 100),'.',(_2{.'00',number 100|scaled),'%'
)
money_text =: 3 : '(number y div 100),''.'',_2{.''00'',number 100|y'
rule_arrow =: 3 : '(itemset_text ''antecedent'' get_key y),'' -> '',itemset_text ''consequent'' get_key y'
text_line =: 3 : 0
    fields =. 0$a:
    for_box. y do.
        value =. >box
        if. 2~:3!:0 value do. value =. number value end.
        fields =. fields,<value
    end.
    ' ' join fields
)
add_line =: 3 : 0
    ReportLines =: ReportLines,<text_line y
    i.0
)
rule_csv_line =: 3 : 0
    fields =. (<number 'rank' get_key y),(<itemset_text 'antecedent' get_key y),(<itemset_text 'consequent' get_key y),<number 'count' get_key y
    for_fieldbox. ' ' split 'support confidence lift leverage conviction improvement' do.
        value =. (>fieldbox) get_key y
        if. 2~:3!:0 value do. value =. fraction_text value end.
        fields =. fields,<value
    end.
    ',' join fields
)
rules_csv =: 3 : 0
    lines =. <'rank,antecedent,consequent,count,support,confidence,lift,leverage,conviction,improvement'
    for_box. y do. lines =. lines,<rule_csv_line >box end.
    lines
)
write_report =: 4 : 0
    ((LF join y),LF#~0<#y) 1!:2 <'output/',x
    i.0
)
