address_peek =: 3 : 0
    if. AddressPosition<#AddressTokens do. 0{::AddressPosition{::AddressTokens else. '' end.
)
address_expect =: 3 : 0
    if. y-:address_peek '' do. AddressPosition =: AddressPosition+1
    else. AddressOkay =: 0 end.
    i.0
)
address_run =: 3 : 0
    start =. AddressPosition
    while. (<address_peek '')e.y do. AddressPosition =: AddressPosition+1 end.
    (AddressPosition-start){.start}.AddressTokens
)
dot_atom =: 3 : 0
    if. 0=2|#y do. 0 return. end.
    for_index. i.#y do.
        kind =. 'word'
        if. 2|index do. kind =. '.' end.
        if. -.kind-:0{::index{::y do. 0 return. end.
    end.
    1
)
token_text =: 3 : 0
    text =. ''
    for_token. y do. text =. text,1{::>token end.
    text
)
display_name =: 3 : 0
    text =. ''
    previous =. 0
    for_index. i.#y do.
        'kind value spaced' =. index{::y
        decoded =. 0
        if. kind-:'word' do.
            'value decoded failed' =. decode_word value
            AddressEncodingError =: AddressEncodingError+.failed
        end.
        if. (index>0)*.spaced*.-.previous*.decoded do. text =. text,' ' end.
        text =. text,value
        previous =. decoded
    end.
    collapse text
)
parse_address =: 3 : 0
    phrase =. address_run 'word';'quoted';'.'
    following =. address_peek ''
    mailboxes =. 0$a:
    if. following-:'<' do.
        AddressPosition =: AddressPosition+1
        local =. address_run 'word';'.'
        address_expect '@'
        domain =. address_run 'word';'.'
        address_expect '>'
        if. (-.AddressOkay)+.(-.dot_atom local)+.-.dot_atom domain do.
            AddressOkay =: 0
            (<0),<mailboxes return.
        end.
        address =. lower (token_text local),'@',token_text domain
        mailbox =. (<display_name phrase),<address
        mailboxes =. ,<mailbox
        (<0),<mailboxes
    elseif. following-:'@' do.
        AddressPosition =: AddressPosition+1
        domain =. address_run 'word';'.'
        if. (-.dot_atom phrase)+.-.dot_atom domain do.
            AddressOkay =: 0
            (<0),<mailboxes return.
        end.
        address =. lower (token_text phrase),'@',token_text domain
        mailbox =. (<''),<address
        mailboxes =. ,<mailbox
        (<0),<mailboxes
    elseif. (following-:':')*.(0<#phrase)*.-.y do.
        AddressPosition =: AddressPosition+1
        if. -.';'-:address_peek '' do.
            parsed =. parse_address 1
            mailboxes =. mailboxes,1{::parsed
            while. AddressOkay*.','-:address_peek '' do.
                AddressPosition =: AddressPosition+1
                parsed =. parse_address 1
                mailboxes =. mailboxes,1{::parsed
            end.
        end.
        address_expect ';'
        (<1),<mailboxes
    else.
        AddressOkay =: 0
        (<0),<mailboxes
    end.
)
parse_address_list =: 3 : 0
    AddressTokens =: 0 tokenize y
    AddressPosition =: 0
    AddressOkay =: TokensOkay*.0<#AddressTokens
    AddressEncodingError =: 0
    addresses =. 0$a:
    if. -.AddressOkay do. (<0),(<addresses),<0 return. end.
    addresses =. addresses,<parse_address 0
    while. AddressOkay*.','-:address_peek '' do.
        AddressPosition =: AddressPosition+1
        addresses =. addresses,<parse_address 0
    end.
    AddressOkay =: AddressOkay*.AddressPosition=#AddressTokens
    (<AddressOkay),(<addresses),<AddressEncodingError
)
