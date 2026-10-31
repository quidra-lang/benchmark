Lower =: 'abcdefghijklmnopqrstuvwxyz'
Upper =: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
Quote =: 34{a.
Slash =: 92{a.
Nil =: _1
Types =: ;:'string list hash set zset'
WrongType =: 'WRONGTYPE Operation against a key holding the wrong kind of value'
NotInt =: 'ERR value is not an integer or out of range'
Overflow =: 'ERR increment or decrement would overflow'
Syntax =: 'ERR syntax error'
Positive =: 'ERR value is out of range, must be positive'
NoKey =: 'ERR no such key'

upper =: 3 : 'a.{~(a.i.y)-32*y e.Lower'
lower =: 3 : 'a.{~(a.i.y)+32*y e.Upper'
number =: 3 : ',''0'' 8!:2 y'
sorted =: 3 : '(/:s:y){y'
emit =: 3 : 'Output =: Output,<y'
fail =: 3 : 0
    Error =: '(error) ',y
    throw.
)
invalid =: 3 : 0
    Error =: 'Invalid argument(s)'
    throw.
)
quoted =: 3 : 0
    if. 2~:3!:0 y do. '(nil)' return. end.
    result =. ,Quote
    for_c. y do.
        if. c e.Quote,Slash do. result =. result,Slash end.
        result =. result,c
    end.
    result,Quote
)
reply_string =: 3 : 'emit quoted y'
reply_int =: 3 : 'emit ''(integer) '',number y'
reply_array =: 3 : 0
    if. 0=#y do. emit '(empty array)' return. end.
    width =. #number #y
    for_i. i.#y do.
        label =. number >:i
        emit ((width-#label)#' '),label,') ',quoted i{::y
    end.
)

tokens =: 3 : 0
    result =. 0$a:
    i =. 0
    while. i<#y do.
        if. ' '=i{y do. i =. >:i continue. end.
        value =. ''
        if. Quote=i{y do.
            i =. >:i
            closed =. 0
            while. i<#y do.
                c =. i{y
                i =. >:i
                if. c=Quote do. closed =. 1 break. end.
                if. c=Slash do.
                    if. i=#y do. invalid '' end.
                    c =. i{y
                    i =. >:i
                    if. -.c e.Quote,Slash do. invalid '' end.
                end.
                value =. value,c
            end.
            if. -.closed do. invalid '' end.
            if. i<#y do.
                if. ' '~:i{y do. invalid '' end.
            end.
        else.
            while. i<#y do.
                if. ' '=i{y do. break. end.
                value =. value,i{y
                i =. >:i
            end.
        end.
        result =. result,<value
    end.
    result
)
is_integer =: 3 : 0
    if. y-:'0' do. 1 return. end.
    if. 0=#y do. 0 return. end.
    if. '-'={.y do. y =. }.y end.
    if. (0=#y)+.9<#y do. 0 return. end.
    (({.y)e.'123456789')*.*./y e.'0123456789'
)
integer =: 3 : 0
    if. -.is_integer y do. fail NotInt end.
    0".y
)
incremented =: 4 : 0
    result =. x+y
    if. 999999999<|result do. fail Overflow end.
    result
)
range =: 4 : 0
    'start stop' =. y
    if. start<0 do. start =. start+x end.
    if. stop<0 do. stop =. stop+x end.
    start =. 0>.start
    stop =. (x-1)<.stop
    if. start>stop do. i.0 else. start+i.1+stop-start end.
)

DbKeys =: 0$a:
DbKinds =: i.0
DbExpiry =: i.0
DbData =: 0$a:
Now =: 0
Stack =: 0$a:
SnapKeys =: 0$a:
SnapData =: 0$a:

snapshot =: 3 : '(<DbKeys),(<DbKinds),(<DbExpiry),<DbData'
restore =: 3 : 0
    'DbKeys DbKinds DbExpiry DbData' =: y
)
locate =: 3 : 0
    at =. DbKeys i.<y
    if. at=#DbKeys do. _1 else. at end.
)
checked =: 4 : 0
    at =. locate y
    if. at>:0 do.
        if. x~:at{DbKinds do. fail WrongType end.
    end.
    at
)
read_value =: 4 : 0
    at =. x checked y
    if. at>:0 do. at{::DbData return. end.
    select. x
    case. 0 do. ''
    case. 2;4 do. 0 2$a:
    case. do. 0$a:
    end.
)
erase =: 3 : 0
    at =. locate y
    if. at<0 do. 0 return. end.
    keep =. at~:i.#DbKeys
    DbKeys =: keep#DbKeys
    DbKinds =: keep#DbKinds
    DbExpiry =: keep#DbExpiry
    DbData =: keep#DbData
    1
)
store_value =: 4 : 0
    'key kind expiry' =. x
    if. (kind~:0)*.0=#y do. erase key return. end.
    at =. locate key
    if. at<0 do.
        DbKeys =: DbKeys,<key
        DbKinds =: DbKinds,kind
        DbExpiry =: DbExpiry,expiry
        DbData =: DbData,<y
    else.
        DbKinds =: kind at}DbKinds
        DbExpiry =: expiry at}DbExpiry
        DbData =: (<y) at}DbData
    end.
    i.0
)
update_value =: 4 : 0
    'key kind' =. x
    expiry =. _1
    at =. locate key
    if. at>:0 do. expiry =. at{DbExpiry end.
    (key;kind;expiry) store_value y
)
purge =: 3 : 0
    expired =. (DbExpiry~:_1)*.DbExpiry<:Now
    count =. +/expired
    DbKeys =: (-.expired)#DbKeys
    DbKinds =: (-.expired)#DbKinds
    DbExpiry =: (-.expired)#DbExpiry
    DbData =: (-.expired)#DbData
    count
)
assoc_put =: 4 : 0
    at =. (0{"1 x)i.{.y
    if. at=#x do. x,y else. y at}x end.
)
assoc_sorted =: 3 : '(/:s:0{"1 y){y'
zsorted =: 3 : 0
    rows =. assoc_sorted y
    (/:>1{"1 rows){rows
)

pattern =: 3 : 0
    parts =. 0$a:
    i =. 0
    while. i<#y do.
        c =. i{y
        i =. >:i
        kind =. 0
        chars =. ,c
        negated =. 0
        if. c=Slash do.
            if. i=#y do. fail 'ERR invalid pattern' end.
            chars =. ,i{y
            i =. >:i
        elseif. c='[' do.
            start =. i
            while. i<#y do.
                if. ']'=i{y do. break. end.
                i =. >:i
            end.
            if. i=#y do. fail 'ERR invalid pattern' end.
            content =. (i-start){.start}.y
            i =. >:i
            if. #content do.
                if. '^'={.content do. negated =. 1 [ content =. }.content end.
            end.
            if. 0=#content do. fail 'ERR invalid pattern' end.
            chars =. ''
            j =. 0
            while. j<#content do.
                if. (j+2)<#content do.
                    if. '-'=(j+1){content do.
                        ends =. a.i.(j,j+2){content
                        low =. <./ends
                        high =. >./ends
                        chars =. chars,a.{~low+i.1+high-low
                        j =. j+3
                        continue.
                    end.
                end.
                chars =. chars,j{content
                j =. >:j
            end.
            kind =. 3
        elseif. c='*' do. kind =. 2
        elseif. c='?' do. kind =. 1
        end.
        parts =. parts,<(kind;chars;negated)
    end.
    parts
)
matches =: 4 : 0
    reachable =. 1,(#y)#0
    for_part. x do.
        'kind chars negated' =. >part
        if. kind=2 do.
            reachable =. +./\reachable
        else.
            if. kind=1 do. accepted =. (#y)#1
            else.
                accepted =. y e.chars
                if. negated do. accepted =. -.accepted end.
            end.
            reachable =. 0,(}:reachable)*.accepted
        end.
    end.
    {:reachable
)
score_bound =: 3 : 0
    if. y-:'-inf' do. _1 0 0 return. end.
    if. y-:'+inf' do. 1 0 0 return. end.
    exclusive =. 0
    if. #y do.
        if. '('={.y do. exclusive =. 1 [ y =. }.y end.
    end.
    if. -.is_integer y do. fail 'ERR min or max is not a float' end.
    0,(0".y),exclusive
)
above =: 4 : 0
    'kind value exclusive' =. x
    if. kind~:0 do. (#y)#kind<0
    elseif. exclusive do. y>value
    else. y>:value end.
)
below =: 4 : 0
    'kind value exclusive' =. x
    if. kind~:0 do. (#y)#kind>0
    elseif. exclusive do. y<value
    else. y<:value end.
)

Args0 =: ;:'TIME DBSIZE FLUSH INFO BEGIN COMMIT ROLLBACK'
Args1 =: ;:'GET INCR DECR STRLEN LLEN HGETALL HLEN HKEYS HVALS SMEMBERS SCARD ZCARD TYPE KEYS TTL PERSIST TICK SNAPSHOT RESTORE'
Args2 =: ;:'INCRBY DECRBY APPEND LINDEX HGET HEXISTS SISMEMBER ZSCORE ZRANK RENAME RENAMENX'
Args3 =: ;:'GETRANGE LRANGE LSET LREM LTRIM HINCRBY ZINCRBY'
Args4 =: ;:'LINSERT'
Args12 =: ;:'LPOP RPOP'
Args23 =: ;:'EXPIRE'
Args34 =: ;:'ZRANGE ZRANGEBYSCORE'
ArgsMany1 =: ;:'MGET SINTER SUNION SDIFF DEL EXISTS'
ArgsMany2 =: ;:'SET LPUSH RPUSH HDEL SADD SREM ZREM SINTERSTORE SUNIONSTORE SDIFFSTORE'
ArgsEven =: ;:'MSET'
ArgsOdd =: ;:'HSET ZADD'
Commands =: Args0,Args1,Args2,Args3,Args4,Args12,Args23,Args34,ArgsMany1,ArgsMany2,ArgsEven,ArgsOdd
arity =: 4 : 0
    cmd =. <x
    if. cmd e.Args0 do. y=0
    elseif. cmd e.Args1 do. y=1
    elseif. cmd e.Args2 do. y=2
    elseif. cmd e.Args3 do. y=3
    elseif. cmd e.Args4 do. y=4
    elseif. cmd e.Args12 do. y e.1 2
    elseif. cmd e.Args23 do. y e.2 3
    elseif. cmd e.Args34 do. y e.3 4
    elseif. cmd e.ArgsMany1 do. y>:1
    elseif. cmd e.ArgsMany2 do. y>:2
    elseif. cmd e.ArgsEven do. (y>:2)*.0=2|y
    else. (y>:3)*.1=2|y end.
)

set_string =: 3 : 0
    key =. 0{::y
    options =. ;:'NX XX EX KEEPTTL GET'
    present =. 5#0
    seconds =. ''
    i =. 2
    while. i<#y do.
        option =. options i.<upper i{::y
        if. option=5 do. fail Syntax end.
        if. option{present do. fail Syntax end.
        present =. 1 option}present
        i =. >:i
        if. option=2 do.
            if. i=#y do. fail Syntax end.
            seconds =. i{::y
            i =. >:i
        end.
    end.
    'nx xx ex keep get' =. present
    if. (nx*.xx)+.ex*.keep do. fail Syntax end.
    if. ex do.
        seconds =. integer seconds
        if. seconds<:0 do. fail 'ERR invalid expire time in ''set'' command' end.
    end.
    at =. locate key
    if. get do. at =. 0 checked key end.
    old =. Nil
    if. get*.at>:0 do. old =. at{::DbData end.
    blocked =. (nx*.at>:0)+.xx*.at<0
    if. -.blocked do.
        expiry =. _1
        if. ex do. expiry =. Now+seconds
        elseif. keep*.at>:0 do. expiry =. at{DbExpiry end.
        (key;0;expiry) store_value 1{::y
    end.
    if. get do. reply_string old
    elseif. blocked do. reply_string Nil
    else. emit 'OK' end.
)
string_command =: 4 : 0
    key =. 0{::y
    select. x
    case. 'SET' do. set_string y
    case. 'GET' do.
        at =. 0 checked key
        if. at<0 do. reply_string Nil else. reply_string at{::DbData end.
    case. 'MSET' do.
        for_i. 2*i.-:#y do. ((i{::y);0;_1) store_value (i+1){::y end.
        emit 'OK'
    case. 'MGET' do.
        items =. 0$a:
        for_name. y do.
            value =. Nil
            at =. locate >name
            if. at>:0 do.
                if. 0=at{DbKinds do. value =. at{::DbData end.
            end.
            items =. items,<value
        end.
        reply_array items
    case. 'INCR';'DECR';'INCRBY';'DECRBY' do.
        delta =. 1
        if. 2=#y do. delta =. integer 1{::y end.
        if. (<x)e.;:'DECR DECRBY' do. delta =. -delta end.
        at =. 0 checked key
        old =. 0
        if. at>:0 do. old =. integer at{::DbData end.
        value =. old incremented delta
        (key;0) update_value number value
        reply_int value
    case. 'APPEND' do.
        value =. (0 read_value key),1{::y
        (key;0) update_value value
        reply_int #value
    case. 'STRLEN' do. reply_int #0 read_value key
    case. 'GETRANGE' do.
        start =. integer 1{::y
        stop =. integer 2{::y
        value =. 0 read_value key
        reply_string ((#value)range start,stop){value
    end.
)
list_command =: 4 : 0
    key =. 0{::y
    select. x
    case. 'LPUSH';'RPUSH' do.
        value =. 1 read_value key
        if. x-:'LPUSH' do. value =. (|.}.y),value
        else. value =. value,}.y end.
        (key;1) update_value value
        reply_int #value
    case. 'LPOP';'RPOP' do.
        count =. 1
        if. 2=#y do.
            if. -.is_integer 1{::y do. fail Positive end.
            count =. 0".1{::y
            if. count<0 do. fail Positive end.
        end.
        at =. 1 checked key
        if. at<0 do. reply_string Nil return. end.
        value =. at{::DbData
        count =. count<.#value
        indices =. i.count
        if. x-:'RPOP' do. indices =. ((#value)-1)-indices end.
        removed =. indices{value
        (key;1) update_value ((-. (i.#value)e.indices)#value)
        if. 2=#y do. reply_array removed else. reply_string 0{::removed end.
    case. 'LRANGE';'LTRIM' do.
        start =. integer 1{::y
        stop =. integer 2{::y
        value =. 1 read_value key
        value =. ((#value)range start,stop){value
        if. x-:'LRANGE' do. reply_array value
        else.
            (key;1) update_value value
            emit 'OK'
        end.
    case. 'LLEN' do. reply_int #1 read_value key
    case. 'LINDEX';'LSET' do.
        index =. integer 1{::y
        at =. 1 checked key
        if. x-:'LSET' do.
            if. at<0 do. fail NoKey end.
        end.
        value =. 0$a:
        if. at>:0 do. value =. at{::DbData end.
        if. index<0 do. index =. index+#value end.
        if. (index<0)+.index>:#value do.
            if. x-:'LSET' do. fail 'ERR index out of range' end.
            reply_string Nil
        elseif. x-:'LINDEX' do. reply_string index{::value
        else.
            (key;1) update_value (2{y) index}value
            emit 'OK'
        end.
    case. 'LREM' do.
        count =. integer 1{::y
        value =. 1 read_value key
        indices =. I.value=2{y
        if. count>0 do. indices =. (count<.#indices){.indices
        elseif. count<0 do. indices =. (-(|count)<.#indices){.indices end.
        (key;1) update_value ((-. (i.#value)e.indices)#value)
        reply_int #indices
    case. 'LINSERT' do.
        where =. upper 1{::y
        if. -.(<where)e.;:'BEFORE AFTER' do. fail Syntax end.
        value =. 1 read_value key
        if. 0=#value do. reply_int 0 return. end.
        at =. value i.2{y
        if. at=#value do. reply_int _1 return. end.
        at =. at+where-:'AFTER'
        value =. (at{.value),(3{y),at}.value
        (key;1) update_value value
        reply_int #value
    end.
)
hash_command =: 4 : 0
    key =. 0{::y
    if. x-:'HINCRBY' do. delta =. integer 2{::y end.
    value =. 2 read_value key
    select. x
    case. 'HSET' do.
        old =. #value
        for_i. 1+2*i.-:<:#y do. value =. value assoc_put (i,i+1){y end.
        (key;2) update_value value
        reply_int (#value)-old
    case. 'HGET' do.
        at =. (0{"1 value)i.1{y
        if. at=#value do. reply_string Nil else. reply_string 1{::at{value end.
    case. 'HDEL' do.
        remove =. (0{"1 value)e.}.y
        (key;2) update_value (-.remove)#value
        reply_int +/remove
    case. 'HGETALL' do. reply_array ,assoc_sorted value
    case. 'HLEN' do. reply_int #value
    case. 'HEXISTS' do. reply_int (1{y)e.0{"1 value
    case. 'HKEYS' do. reply_array 0{"1 assoc_sorted value
    case. 'HVALS' do. reply_array 1{"1 assoc_sorted value
    case. 'HINCRBY' do.
        at =. (0{"1 value)i.1{y
        old =. 0
        if. at<#value do.
            text =. 1{::at{value
            if. -.is_integer text do. fail 'ERR hash value is not an integer' end.
            old =. 0".text
        end.
        result =. old incremented delta
        (key;2) update_value value assoc_put (1{y),<number result
        reply_int result
    end.
)
set_command =: 4 : 0
    if. (<x)e.;:'SINTER SUNION SDIFF SINTERSTORE SUNIONSTORE SDIFFSTORE' do.
        saving =. 'STORE'-:_5{.x
        sources =. y
        if. saving do. sources =. }.y end.
        sets =. 0$a:
        for_key. sources do. sets =. sets,<3 read_value >key end.
        value =. 0{::sets
        for_other. }.sets do.
            if. 'SINTER'-:6{.x do. value =. (value e.>other)#value
            elseif. 'SUNION'-:6{.x do. value =. ~.value,>other
            else. value =. (-.value e.>other)#value end.
        end.
        if. saving do.
            ((0{::y);3;_1) store_value value
            reply_int #value
        else. reply_array sorted value end.
        return.
    end.
    key =. 0{::y
    value =. 3 read_value key
    select. x
    case. 'SADD' do.
        old =. #value
        value =. ~.value,}.y
        (key;3) update_value value
        reply_int (#value)-old
    case. 'SREM' do.
        remove =. value e.}.y
        (key;3) update_value (-.remove)#value
        reply_int +/remove
    case. 'SISMEMBER' do. reply_int (1{y)e.value
    case. 'SMEMBERS' do. reply_array sorted value
    case. 'SCARD' do. reply_int #value
    end.
)
zset_command =: 4 : 0
    key =. 0{::y
    select. x
    case. 'ZADD' do.
        scores =. i.0
        for_i. 1+2*i.-:<:#y do. scores =. scores,integer i{::y end.
        value =. 4 read_value key
        old =. #value
        for_i. i.#scores do.
            value =. value assoc_put ((2+2*i){y),<i{scores
        end.
        (key;4) update_value value
        reply_int (#value)-old
    case. 'ZINCRBY' do.
        delta =. integer 1{::y
        value =. 4 read_value key
        at =. (0{"1 value)i.2{y
        old =. 0
        if. at<#value do. old =. 1{::at{value end.
        result =. old incremented delta
        (key;4) update_value value assoc_put (2{y),<result
        reply_string number result
    case. 'ZSCORE';'ZRANK' do.
        value =. 4 read_value key
        if. x-:'ZRANK' do. value =. zsorted value end.
        at =. (0{"1 value)i.1{y
        if. at=#value do. reply_string Nil
        elseif. x-:'ZRANK' do. reply_int at
        else. reply_string number 1{::at{value end.
    case. 'ZREM' do.
        value =. 4 read_value key
        remove =. (0{"1 value)e.}.y
        (key;4) update_value (-.remove)#value
        reply_int +/remove
    case. 'ZCARD' do. reply_int #4 read_value key
    case. 'ZRANGE';'ZRANGEBYSCORE' do.
        withscores =. 4=#y
        if. withscores do.
            if. -.'WITHSCORES'-:upper 3{::y do. fail Syntax end.
        end.
        if. x-:'ZRANGE' do.
            start =. integer 1{::y
            stop =. integer 2{::y
            value =. zsorted 4 read_value key
            value =. ((#value)range start,stop){value
        else.
            minimum =. score_bound 1{::y
            maximum =. score_bound 2{::y
            value =. zsorted 4 read_value key
            scores =. >1{"1 value
            value =. ((minimum above scores)*.maximum below scores)#value
        end.
        items =. 0{"1 value
        if. withscores do.
            items =. 0$a:
            for_row. value do.
                items =. items,(0{row),<number 1{::row
            end.
        end.
        reply_array items
    end.
)
key_command =: 4 : 0
    select. x
    case. 'DEL' do.
        removed =. 0
        for_key. y do. removed =. removed+erase >key end.
        reply_int removed
    case. 'EXISTS' do. reply_int +/y e.DbKeys
    case. 'TYPE' do.
        at =. locate 0{::y
        if. at<0 do. emit 'none' else. emit (at{DbKinds){::Types end.
    case. 'RENAME';'RENAMENX' do.
        'key destination' =. y
        at =. locate key
        if. at<0 do. fail NoKey end.
        if. x-:'RENAMENX' do.
            if. 0<:locate destination do. reply_int 0 return. end.
        end.
        if. -.key-:destination do.
            record =. destination;(at{DbKinds);at{DbExpiry
            value =. at{::DbData
            erase key
            record store_value value
        end.
        if. x-:'RENAME' do. emit 'OK' else. reply_int 1 end.
    case. 'KEYS' do.
        parts =. pattern 0{::y
        found =. 0$a:
        for_key. DbKeys do.
            if. parts matches >key do. found =. found,key end.
        end.
        reply_array sorted found
    case. 'EXPIRE' do.
        condition =. ''
        if. 3=#y do.
            condition =. upper 2{::y
            if. -.(<condition)e.;:'NX XX GT LT' do. fail 'ERR Unsupported option ',2{::y end.
        end.
        seconds =. integer 1{::y
        key =. 0{::y
        at =. locate key
        if. at<0 do. reply_int 0 return. end.
        old =. at{DbExpiry
        expiry =. Now+seconds
        rejected =. 0
        select. condition
        case. 'NX' do. rejected =. old~:_1
        case. 'XX' do. rejected =. old=_1
        case. 'GT' do. rejected =. (old=_1)+.expiry<:old
        case. 'LT' do. rejected =. (old~:_1)*.expiry>:old
        end.
        if. rejected do. reply_int 0 return. end.
        if. seconds<:0 do. erase key
        else. DbExpiry =: expiry at}DbExpiry end.
        reply_int 1
    case. 'TTL' do.
        at =. locate 0{::y
        if. at<0 do. reply_int _2
        elseif. _1=at{DbExpiry do. reply_int _1
        else. reply_int (at{DbExpiry)-Now end.
    case. 'PERSIST' do.
        at =. locate 0{::y
        if. at>:0 do.
            if. _1~:at{DbExpiry do.
                DbExpiry =: _1 at}DbExpiry
                reply_int 1 return.
            end.
        end.
        reply_int 0
    case. 'TICK' do.
        ticks =. integer 0{::y
        if. ticks<:0 do. fail Positive end.
        Now =: Now+ticks
        reply_int purge ''
    case. 'TIME' do. reply_int Now
    case. 'DBSIZE' do. reply_int #DbKeys
    case. 'FLUSH' do.
        DbKeys =: DbData =: 0$a:
        DbKinds =: DbExpiry =: i.0
        emit 'OK'
    case. 'INFO' do.
        text =. 'keys=',(number #DbKeys),',expires=',number +/DbExpiry~:_1
        for_i. i.5 do. text =. text,',',(i{::Types),'=',number +/DbKinds=i end.
        emit text,',time=',(number Now),',depth=',(number #Stack),',snapshots=',number #SnapKeys
    end.
)
control_command =: 4 : 0
    select. x
    case. 'BEGIN' do. Stack =: Stack,<snapshot ''
    case. 'COMMIT';'ROLLBACK' do.
        if. 0=#Stack do. fail 'ERR no transaction' end.
        if. x-:'ROLLBACK' do.
            restore _1{::Stack
            purge ''
        end.
        Stack =: }:Stack
    case. 'SNAPSHOT' do.
        at =. SnapKeys i.{.y
        value =. <snapshot ''
        if. at=#SnapKeys do.
            SnapKeys =: SnapKeys,{.y
            SnapData =: SnapData,value
        else. SnapData =: value at}SnapData end.
    case. 'RESTORE' do.
        at =. SnapKeys i.{.y
        if. at=#SnapKeys do. fail 'ERR no such snapshot' end.
        restore at{::SnapData
        purge ''
    end.
    emit 'OK'
)

Strings =: ;:'SET GET MSET MGET INCR DECR INCRBY DECRBY APPEND STRLEN GETRANGE'
Lists =: ;:'LPUSH RPUSH LPOP RPOP LRANGE LLEN LINDEX LSET LREM LTRIM LINSERT'
Hashes =: ;:'HSET HGET HDEL HGETALL HLEN HEXISTS HKEYS HVALS HINCRBY'
Sets =: ;:'SADD SREM SISMEMBER SMEMBERS SCARD SINTER SUNION SDIFF SINTERSTORE SUNIONSTORE SDIFFSTORE'
Zsets =: ;:'ZADD ZSCORE ZINCRBY ZREM ZCARD ZRANK ZRANGE ZRANGEBYSCORE'
Controls =: ;:'BEGIN COMMIT ROLLBACK SNAPSHOT RESTORE'
execute =: 3 : 0
    Output =: 0$a:
    words =. tokens y
    cmd =. upper 0{::words
    if. -.(<cmd)e.Commands do. fail 'ERR unknown command ''',(0{::words),'''' end.
    args =. }.words
    if. -.cmd arity #args do. fail 'ERR wrong number of arguments for ''',(lower cmd),''' command' end.
    if. (<cmd)e.Strings do. cmd string_command args
    elseif. (<cmd)e.Lists do. cmd list_command args
    elseif. (<cmd)e.Hashes do. cmd hash_command args
    elseif. (<cmd)e.Sets do. cmd set_command args
    elseif. (<cmd)e.Zsets do. cmd zset_command args
    elseif. (<cmd)e.Controls do. cmd control_command args
    else. cmd key_command args end.
    Output
)
main =: 3 : 0
    count =. 0".1!:1[3
    for_command. i.count do.
        line =. 1!:1[3
        try. rows =. execute line
        catcht. rows =. <Error end.
        for_row. rows do. ((>row),LF) 1!:2[4 end.
    end.
)
main ''
2!:55[0
