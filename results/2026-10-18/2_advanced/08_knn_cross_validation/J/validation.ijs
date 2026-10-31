model_record =: 3 : '''k metric weighting scaling'' record y'
model_text =: 3 : '''k='',(number ''k'' get_key y),'' metric='',(''metric'' get_key y),'' weighting='',(''weighting'' get_key y),'' scaling='',''scaling'' get_key y'
stratified_folds =: 4 : 0
    keys =. 0 2$a:
    for_box. y do. keys =. keys,1 2$(<'label' get_key >box),<'id' get_key >box end.
    ordered =. /:keys
    folds =. x#<0$0
    for_position. i.#ordered do.
        index =. x|position
        fold =. (index{::folds),position{ordered
        folds =. (<fold) index}folds
    end.
    /:~&.>folds
)
neighbor_orders =: 3 : 0
    'training queries method metric features' =. y
    scaling =. method compute_scaling training
    references =. 0$a:
    for_box. training do.
        row =. >box
        vector =. transform_values (<scaling),(<'values' get_key row),<features
        references =. references,<(<vector),<row
    end.
    orders =. 0$a:
    for_box. queries do.
        vector =. transform_values (<scaling),(<'values' get_key >box),<features
        orders =. orders,<neighbor_order (<vector),(<references),<metric
    end.
    orders
)
prediction_from_order =: 3 : 0
    'order k weighting' =. y
    nearest =. (k<.#order){.order
    prediction =. weighting vote nearest
    prediction =. ((<'estimate'),<weighting estimate nearest) put_key prediction
    ((<'neighbors'),<nearest) put_key prediction
)
predict_rows =: 3 : 0
    'model training queries features' =. y
    orders =. neighbor_orders (<training),(<queries),(<'scaling' get_key model),(<'metric' get_key model),<features
    predictions =. 0$a:
    for_box. orders do. predictions =. predictions,<prediction_from_order box,(<'k' get_key model),<'weighting' get_key model end.
    predictions
)
rmse =: 3 : '%:(real_sum y*y)%real #y'
mae =: 3 : '(real_sum |y)%real #y'
r_squared =: 4 : 0
    mean =. (real_sum y)%real #y
    differences =. y-mean
    1.0-(real_sum x*x)%real_sum differences*differences
)
