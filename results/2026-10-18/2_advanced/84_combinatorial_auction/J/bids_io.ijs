read_inputs =: 3 : 0
    ItemNames =: 0$a:
    Reserves =: i.0
    for_fields. records 'items.txt' do.
        fields =. >fields
        ItemNames =: ItemNames,<0{::fields
        Reserves =: Reserves,parse_integer 1{::fields
    end.
    ItemCount =: #ItemNames
    RawNames =: 0$a:
    RawOffers =: 0$a:
    RawLines =: 0$a:
    for_fields. records 'bids.txt' do.
        fields =. >fields
        if. 'auction'-:0{::fields do.
            RawNames =: RawNames,<1{::fields
            RawOffers =: RawOffers,<ItemNames i.2}.fields
            RawLines =: RawLines,<0$a:
        else.
            index =. (#RawNames)-1
            line =. (1{fields),(2{fields),<3}.fields
            RawLines =: (<(index{::RawLines),<line)index}RawLines
        end.
    end.
    Groups =: 0$a:
    for_fields. records 'single_item.txt' do.
        fields =. >fields
        if. (<0{::fields)e.;:'lot slots' do.
            group =. (0{fields),(1{fields),(<2}.fields),<0$a:
            Groups =: Groups,<group
        else.
            index =. (#Groups)-1
            group =. index{::Groups
            participant =. (1{fields),(<parse_integer 2{::fields),<parse_integer 3{::fields
            participants =. (3{::group),<participant
            group =. (<participants)3}group
            Groups =: (<group)index}Groups
        end.
    end.
    ParameterNames =: 0$a:
    ParameterValues =: 0$a:
    for_fields. records 'params.txt' do.
        fields =. >fields
        name =. 0{::fields
        value =. }.fields
        if. -.name-:'run' do.
            value =. parse_integer 1{::fields
        end.
        ParameterNames =: ParameterNames,<name
        ParameterValues =: ParameterValues,<value
    end.
)
parameter =: 3 : '(ParameterNames i.<y){::ParameterValues'
new_bid =: 4 : 0
    'number bidder xor' =. x
    'bundle amount' =. y
    number,bidder,bundle,amount,xor
)
