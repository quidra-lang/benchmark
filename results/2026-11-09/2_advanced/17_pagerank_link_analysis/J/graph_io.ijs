read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
read_input =: 3 : 0
    Pages =: 0$a:
    for_box. }.read_lines 'pages.csv' do.
        fields =. ',' split >box
        Pages =: Pages,<(<num 0{::fields),(1{fields),(2{fields),<' ' split 2{::fields
    end.
    Pages =: (/: (0&{::)&>Pages){Pages
    PageIds =: (0&{::)&>Pages
    PageHosts =: (1&{::)&.>Pages
    PageCount =: #Pages
    Records =: 0 3$0
    lines =. }.read_lines 'links.csv'
    for_index. i.#lines do. Records =: Records,(index+2),num&>',' split index{::lines end.
    Queries =: 0$a:
    for_index. i.#read_lines 'queries.txt' do.
        parts =. '|' split index{::read_lines 'queries.txt'
        words =. ' ' split }:0{::parts
        seeds =. num&>' ' split }.1{::parts
        Queries =: Queries,<(<index+1),(<words),<seeds
    end.
    fields =. 0$a:
    for_box. read_lines 'params.txt' do. fields =. fields,<}.' ' split >box end.
    Damping =: decimal 0{::0{::fields
    Iterations =: num 0{::1{::fields
    Tolerance =: decimal 0{::2{::fields
    Sweep =: decimal&>3{::fields
    Trusted =: num&>4{::fields
    SpamTop =: num 0{::5{::fields
    SpamThreshold =: decimal 0{::6{::fields
    HitsIterations =: num 0{::7{::fields
    TopK =: num 0{::8{::fields
    RootLimit =: num 0{::9{::fields
    NeighborLimit =: num 0{::10{::fields
    i.0
)
