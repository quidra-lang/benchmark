initialize_clients =: 3 : 0
    ClientIds =: 0$a:
    Hosts =: 0$a:
    Nicknames =: 0$a:
    Usernames =: 0$a:
    Realnames =: 0$a:
    AwayMessages =: 0$a:
    Queues =: 0$a:
    Joined =: 0$a:
    Invites =: 0$a:
    Active =: i.0
    Invisible =: i.0
    Registered =: i.0
    ConnectionTimes =: i.0
    SignonTimes =: i.0
    LastReceived =: i.0
    LastSpeaking =: i.0
    PingTimes =: i.0
    Tokens =: i.0
    RefillTimes =: i.0
    ReceivedCounts =: i.0
    SentCounts =: i.0
    i.0
)
new_client =: 3 : 0
    'identifier host time capacity' =. y
    index =. #ClientIds
    ClientIds =: ClientIds,<identifier
    Hosts =: Hosts,<host
    Nicknames =: Nicknames,<''
    Usernames =: Usernames,<''
    Realnames =: Realnames,<''
    AwayMessages =: AwayMessages,<''
    Queues =: Queues,<0$a:
    Joined =: Joined,<i.0
    Invites =: Invites,<i.0
    Active =: Active,1
    Invisible =: Invisible,0
    Registered =: Registered,0
    ConnectionTimes =: ConnectionTimes,time
    SignonTimes =: SignonTimes,_1
    LastReceived =: LastReceived,time
    LastSpeaking =: LastSpeaking,_1
    PingTimes =: PingTimes,_1
    Tokens =: Tokens,capacity
    RefillTimes =: RefillTimes,_1
    ReceivedCounts =: ReceivedCounts,0
    SentCounts =: SentCounts,0
    index
)
addressee =: 3 : 0
    name =. y{::Nicknames
    if. #name do.
        name
    else.
        '*'
    end.
)
prefix =: 3 : '(y{::Nicknames),''!'',(y{::Usernames),''@'',y{::Hosts'
client_mode =: 3 : 0
    if. y{Invisible do.
        '+i'
    else.
        '+'
    end.
)
use_token =: 3 : 0
    if. BucketCapacity=y{Tokens do.
        RefillTimes =: (CurrentTime+RefillInterval)y}RefillTimes
    end.
    Tokens =: ((y{Tokens)-1)y}Tokens
    i.0
)
refill_tokens =: 3 : 0
    if. CurrentTime=y{RefillTimes do.
        value =. 1+y{Tokens
        Tokens =: value y}Tokens
        time =. _1
        if. value<BucketCapacity do.
            time =. CurrentTime+RefillInterval
        end.
        RefillTimes =: time y}RefillTimes
    end.
    i.0
)
