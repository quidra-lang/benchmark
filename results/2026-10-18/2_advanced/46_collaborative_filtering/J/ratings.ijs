read_lines =: 3 : '<;._2 (1!:1 <y)'
words =: 3 : '<;._1 '' '',y'
decimal =: 3 : '0.0+0".y'
integer_value =: 3 : '0".y'
integers_csv =: 3 : 0
    lines =. }.read_lines y
    rows =. 0$a:
    for_line. lines do.
        fields =. <;._1 ',',>line
        rows =. rows,<integer_value&>fields
    end.
    >rows
)
read_inputs =: 3 : 0
    raw =. integers_csv 'input/ratings.csv'
    Users =: /:~~.0{"1 raw
    Items =: /:~~.1{"1 raw
    RatingValues =: ((#Users),#Items)$0
    Training =: 0 4$0
    for_row. raw do.
        u =. Users i.0{row
        i =. Items i.1{row
        RatingValues =: (2{row)(<u,i)}RatingValues
        Training =: Training,u,i,2 3{row
    end.
    UserRatings =: 0$a:
    ItemRatings =: 0$a:
    UserCounts =: i.0
    ItemCounts =: i.0
    UserMeans =: i.0
    ItemMeans =: i.0
    for_u. i.#Users do.
        rated =. I.0<u{RatingValues
        UserRatings =: UserRatings,<rated
        UserCounts =: UserCounts,#rated
        UserMeans =: UserMeans,((0.0++/rated{u{RatingValues)%#rated)
    end.
    for_i. i.#Items do.
        rated =. I.0<i{"1 RatingValues
        ItemRatings =: ItemRatings,<rated
        ItemCounts =: ItemCounts,#rated
        ItemMeans =: ItemMeans,((0.0++/rated{i{"1 RatingValues)%#rated)
    end.
    GlobalMean =: (0.0++/2{"1 Training)%#Training
    Testing =: 0 3$0
    for_row. integers_csv 'input/test.csv' do.
        Testing =: Testing,(Users i.0{row),(Items i.1{row),2{row
    end.
    CatalogIDs =: i.0
    Titles =: 0$a:
    GenreTexts =: 0$a:
    Genres =: 0$a:
    for_line. }.read_lines 'input/items.csv' do.
        fields =. <;._1 ',',>line
        CatalogIDs =: CatalogIDs,integer_value 0{::fields
        Titles =: Titles,1{fields
        GenreTexts =: GenreTexts,2{fields
        Genres =: Genres,< <;._1 '|',2{::fields
    end.
    ItemCatalog =: CatalogIDs i.Items
    settings =. words&.>read_lines 'input/params.txt'
    Neighbors =: <.decimal 1{::0{::settings
    Shrinkage =: <.decimal 1{::1{::settings
    MinSimilarity =: decimal 1{::2{::settings
    ItemReg =: decimal 1{::3{::settings
    UserReg =: decimal 2{::3{::settings
    FactorCount =: <.decimal 1{::4{::settings
    LearningRate =: decimal 1{::5{::settings
    Regularization =: decimal 1{::6{::settings
    Epochs =: <.decimal 1{::7{::settings
    AlsReg =: decimal 1{::8{::settings
    AlsIterations =: <.decimal 1{::9{::settings
    Seed =: <.decimal 1{::10{::settings
    TopN =: <.decimal 1{::11{::settings
    Cutoffs =: <.decimal&>}.12{::settings
    NeighborGrid =: <.decimal&>}.13{::settings
    UserGroups =: integer_value&>}.14{::settings
    ItemGroups =: integer_value&>}.15{::settings
    TimeBuckets =: <.decimal 1{::16{::settings
    ListSize =: <.decimal 1{::17{::settings
    RecommendUsers =: integer_value&>}.18{::settings
    SimilarItems =: integer_value&>}.19{::settings
    0
)
