address_of =: 3 : '16{.digest ''addr:'',y'
sign =: 3 : 0
    'secret index body' =. y
    16{.digest secret,':',(":index),':',body
)
read_wallets =: 3 : 0
    result =. 0$a:
    for_line. <;._2 (1!:1 <y) do.
        'name secret' =. ' 'split >line
        result =. result,<(<name),(<secret),<address_of secret
    end.
    result
)
wallet_name =: 0&{::
wallet_secret =: 1&{::
wallet_address =: 2&{::
