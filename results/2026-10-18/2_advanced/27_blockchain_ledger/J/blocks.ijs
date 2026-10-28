b_height =: 0&{::
b_previous =: 1&{::
b_merkle =: 2&{::
b_time =: 3&{::
b_difficulty =: 4&{::
b_nonce =: 5&{::
b_transactions =: 6&{::
b_hash =: 7&{::
b_txids =: tx_id&.>@b_transactions
b_size =: 3 : '+/tx_size&>}.b_transactions y'
header_text =: 3 : '''|''join text&.>y'
make_block =: 3 : 'y,<digest header_text 6{.y'
meets_difficulty =: 4 : '(y#''0'')-:y{.x'
parse_block_event =: 3 : 0
    'fields texts' =. y
    height =. num 3{::fields
    previous =. 4{::fields
    merkle =. 5{::fields
    'timestamp difficulty nonce' =. num&>6 7 8{fields
    transactions =. parse_transaction&.>texts
    make_block (<height),(<previous),(<merkle),(<timestamp),(<difficulty),(<nonce),<transactions
)
mine_block =: 3 : 0
    'height previous transactions timestamp difficulty' =. y
    merkle =. merkle_root tx_id&.>transactions
    nonce =. 0
    while. 1 do.
        block =. make_block (<height),(<previous),(<merkle),(<timestamp),(<difficulty),(<nonce),<transactions
        if. (b_hash block)meets_difficulty difficulty do.
            block return.
        end.
        nonce =. nonce+1
    end.
)
context_free_error =: 4 : 0
    if. -.(b_hash y)meets_difficulty b_difficulty y do.
        'bad-pow' return.
    end.
    if. -.(merkle_root b_txids y)-:b_merkle y do.
        'bad-merkle' return.
    end.
    transactions =. b_transactions y
    first =. 0{::transactions
    if. (-.is_coinbase first)+.(tx_coinbase_height first)~:b_height y do.
        'bad-structure' return.
    end.
    if. +./is_coinbase&>}.transactions do.
        'bad-structure' return.
    end.
    if. (b_size y)>x do.
        'too-large' return.
    end.
    ''
)
