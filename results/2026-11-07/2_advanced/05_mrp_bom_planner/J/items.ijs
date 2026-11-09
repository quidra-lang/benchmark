LotRules =: ' ' split 'LFL FOQ POQ MIN'
lot_values =: 4 : 0
    values =. num&>'/' split y
    if. x-:'LFL' do. fits =. ((#values)=1)*.0={.values
    elseif. x-:'MIN' do. fits =. ((#values)=2)*.*./values>:1
    else. fits =. ((#values)=1)*.1<:{.values end.
    (<fits),<values
)
lot_label =: 3 : 0
    rule =. 'rule' get_key y
    if. rule-:'LFL' do. rule return. end.
    values =. 'lot' get_key y
    if. rule-:'MIN' do. rule,' ',(number 0{values),'/',number 1{values
    else. rule,' ',number {.values end.
)
read_items =: 3 : 0
    Items =: empty_table ''
    for_box. read_rows 'items.csv' do.
        'line fields' =. >box
        'id leadtext rule lottext safetytext handtext materialtext labortext description' =. fields
        reason =. ''
        lot =. 0$0
        if. id has_key Items do. reason =. 'duplicate item ',id
        elseif. -.(<rule)e.LotRules do. reason =. 'unknown lot rule ',rule
        else.
            'fits lot' =. rule lot_values lottext
            if. -.fits do. reason =. 'bad lot parameter ',lottext,' for ',rule end.
        end.
        if. #reason do. 'items.csv' record_error (<line),<reason
        else.
            values =. (<id),(<num leadtext),(<rule),(<lot),(<num safetytext),(<num handtext),(<num materialtext),(<num labortext),<description
            item =. 'id lead_time rule lot safety_stock on_hand material labor description' record values
            Items =: ((<id),<item) put_key Items
        end.
    end.
    i.0
)
