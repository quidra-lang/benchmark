query_tokens =: 3 : 0
    tokens =. 0$a:
    position =. 0
    letters =. 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_'
    digits =. '0123456789'
    while. position<#y do.
        character =. position{y
        if. character=' ' do.
            position =. position+1
            continue.
        end.
        start =. position
        position =. position+1
        if. character='''' do.
            while. ''''~:position{y do.
                position =. position+1
            end.
            position =. position+1
        elseif. character e.letters do.
            while. position<#y do.
                if. -.(position{y)e.letters,digits do.
                    break.
                end.
                position =. position+1
            end.
        elseif. character e.digits,'-' do.
            while. position<#y do.
                if. -.(position{y)e.digits do.
                    break.
                end.
                position =. position+1
            end.
        elseif. (<2{.start}.y)e.'<=';'>=';'<>' do.
            position =. position+1
        end.
        tokens =. tokens,<(position-start){.start}.y
    end.
    tokens
)
query_peek =: 3 : 0
    if. QueryPosition=#QueryTokens do.
        ''
    else.
        QueryPosition{::QueryTokens
    end.
)
query_take =: 3 : 0
    value =. QueryPosition{::QueryTokens
    QueryPosition =: QueryPosition+1
    value
)
query_accept =: 3 : 0
    if. y-:query_peek '' do.
        QueryPosition =: QueryPosition+1
        1
    else.
        0
    end.
)
query_literal =: 3 : 0
    token =. query_take ''
    if. ''''={.token do.
        (<1),<}.}:token
    elseif. (<token)e.;:'TRUE FALSE' do.
        (<2),<token-:'TRUE'
    else.
        (<0),<parse_integer token
    end.
)
query_item =: 3 : 0
    operation =. query_take ''
    if. ({.operation)e.'abcdefghijklmnopqrstuvwxyz' do.
        (<'COLUMN'),<operation return.
    end.
    query_take ''
    if. query_accept 'DISTINCT' do.
        operation =. 'COUNT_DISTINCT'
    end.
    name =. query_take ''
    query_take ''
    (<operation),<name
)
query_condition =: 3 : 0
    tree =. query_conjunction ''
    while. query_accept 'OR' do.
        right =. query_conjunction ''
        tree =. (<'OR'),(<tree),<right
    end.
    tree
)
query_conjunction =: 3 : 0
    tree =. query_negation ''
    while. query_accept 'AND' do.
        right =. query_negation ''
        tree =. (<'AND'),(<tree),<right
    end.
    tree
)
query_negation =: 3 : 0
    if. query_accept 'NOT' do.
        (<'NOT'),<query_negation '' return.
    end.
    if. query_accept '(' do.
        tree =. query_condition ''
        query_take ''
        tree return.
    end.
    name =. query_take ''
    operation =. query_take ''
    literals =. 0$a:
    if. operation-:'IS' do.
        operation =. 'IS_NULL'
        if. query_accept 'NOT' do.
            operation =. 'IS_NOT_NULL'
        end.
        query_take ''
    elseif. operation-:'BETWEEN' do.
        literals =. <query_literal ''
        query_take ''
        literals =. literals,<query_literal ''
    elseif. operation-:'IN' do.
        query_take ''
        literals =. <query_literal ''
        while. query_accept ',' do.
            literals =. literals,<query_literal ''
        end.
        query_take ''
    else.
        literals =. <query_literal ''
    end.
    (<operation),(<name),<literals
)
parse_query =: 3 : 0
    QueryTokens =: query_tokens y
    QueryPosition =: 0
    query_take ''
    if. query_accept '*' do.
        items =. ,<'*'
    else.
        items =. <query_item ''
        while. query_accept ',' do.
            items =. items,<query_item ''
        end.
    end.
    condition =. 0$a:
    if. query_accept 'WHERE' do.
        condition =. query_condition ''
    end.
    group =. ''
    if. query_accept 'GROUP' do.
        query_take ''
        group =. query_take ''
    end.
    order =. ''
    descending =. 0
    if. query_accept 'ORDER' do.
        query_take ''
        order =. query_take ''
        if. query_accept 'DESC' do.
            descending =. 1
        else.
            query_accept 'ASC'
        end.
    end.
    limit =. 0
    if. query_accept 'LIMIT' do.
        limit =. parse_integer query_take ''
    end.
    (<items),(<condition),(<group),(<order),(<descending),<limit
)
