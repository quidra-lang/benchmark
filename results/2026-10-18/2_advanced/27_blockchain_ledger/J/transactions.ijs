tx_text =: 0&{::
tx_id =: 1&{::
tx_size =: 2&{::
tx_inputs =: 3&{::
tx_addresses =: 4&{::
tx_amounts =: 5&{::
tx_signatures =: 6&{::
tx_coinbase_height =: 7&{::
is_coinbase =: 3 : '0<:tx_coinbase_height y'
tx_total =: +/@tx_amounts
tx_body =: 3 : 0
    text =. tx_text y
    ({.I.';sig=' E.text){.text
)
make_transaction =: 3 : 0
    'text inputs addresses amounts signatures height' =. y
    (<text),(<digest text),(<#text),(<inputs),(<addresses),(<amounts),(<signatures),<height
)
parse_outputs =: 3 : 0
    addresses =. 0$a:
    amounts =. i.0
    for_piece. ','split y do.
        'address amount' =. ':'split >piece
        addresses =. addresses,<address
        amounts =. amounts,num amount
    end.
    (<addresses),<amounts
)
outputs_text =: 3 : 0
    'addresses amounts' =. y
    parts =. 0$a:
    for_i. i.#addresses do.
        parts =. parts,<(i{::addresses),':',":i{amounts
    end.
    ','join parts
)
parse_transaction =: 3 : 0
    parts =. ';'split y
    'addresses amounts' =. parse_outputs 4}.1{::parts
    first =. 0{::parts
    if. 'cb='-:3{.first do.
        make_transaction (<y),(<0$a:),(<addresses),(<amounts),(<0$a:),<num 3}.first
    else.
        inputs =. ','split 3}.first
        signatures =. ','split 4}.2{::parts
        make_transaction (<y),(<inputs),(<addresses),(<amounts),(<signatures),<_1
    end.
)
create_transaction =: 3 : 0
    'inputs addresses amounts secret' =. y
    body =. 'in=',(','join inputs),';out=',outputs_text (<addresses),<amounts
    signatures =. 0$a:
    for_i. i.#inputs do.
        signatures =. signatures,<sign (<secret),(<i),<body
    end.
    text =. body,';sig=',','join signatures
    make_transaction (<text),(<inputs),(<addresses),(<amounts),(<signatures),<_1
)
create_coinbase =: 3 : 0
    'height addresses amounts' =. y
    text =. 'cb=',(":height),';out=',outputs_text (<addresses),<amounts
    make_transaction (<text),(<0$a:),(<addresses),(<amounts),(<0$a:),<height
)
coin_address =: 0&{::
coin_amount =: 1&{::
coin_height =: 2&{::
coin_coinbase =: 3&{::
is_mature =: 4 : 0
    'height maturity' =. y
    (-.coin_coinbase x)+.(0=coin_height x)+.height>:(coin_height x)+maturity
)
check_transaction =: 3 : 0
    'transaction utxo spent height owners maturity' =. y
    addresses =. tx_addresses transaction
    amounts =. tx_amounts transaction
    known =. wallet_address&.>owners
    if. (0 e.amounts)+.-.*./addresses e.known do.
        'bad-output';0 return.
    end.
    'references coins' =. utxo
    seen =. 0$a:
    total =. 0
    inputs =. tx_inputs transaction
    signatures =. tx_signatures transaction
    for_i. i.#inputs do.
        reference =. i{inputs
        if. (reference e.spent)+.reference e.seen do.
            'double-spend';0 return.
        end.
        if. -.reference e.references do.
            'missing-input';0 return.
        end.
        coin =. (references i.reference){::coins
        if. -.coin is_mature height,maturity do.
            'immature';0 return.
        end.
        owner =. (known i.<coin_address coin){::owners
        expected =. sign (<wallet_secret owner),(<i),<tx_body transaction
        if. -.expected-:i{::signatures do.
            'bad-sig';0 return.
        end.
        seen =. seen,reference
        total =. total+coin_amount coin
    end.
    amount =. tx_total transaction
    if. total<amount do.
        'overspend';0 return.
    end.
    '';total-amount
)
apply_transaction =: 4 : 0
    'transaction height' =. y
    'references coins' =. x
    keep =. -.references e.tx_inputs transaction
    references =. keep#references
    coins =. keep#coins
    addresses =. tx_addresses transaction
    amounts =. tx_amounts transaction
    for_i. i.#addresses do.
        reference =. (tx_id transaction),':',":i
        coin =. (i{addresses),(<i{amounts),(<height),<is_coinbase transaction
        position =. references i.<reference
        if. position<#references do.
            coins =. (<coin)position}coins
        else.
            references =. references,<reference
            coins =. coins,<coin
        end.
    end.
    (<references),<coins
)
