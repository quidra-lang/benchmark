path_text =: 3 : ''',''join integer&.>y'
attribute_text =: 3 : 0
    'path origin med communities' =. y
    'path ',(path_text path),' origin ',(origin{::Origins),' med ',(integer med),' comm ',communities_text communities
)
route_text =: 3 : 0
    if. 0=#y do.
        'NONE' return.
    end.
    'path origin med communities local_pref link' =. y
    suffix =. 'origin ',(origin{::Origins),' comm ',communities_text communities
    if. link=_1 do.
        'LOCAL ',suffix
    else.
        line =. 'next ',(integer {.path),' path ',(path_text path),' link ',link{::LinkNames
        line,' lp ',(integer local_pref),' med ',(integer med),' ',suffix
    end.
)
message_text =: 3 : 0
    line =. '#',(integer y+1),' ',(integer (y{MsgSender){ASNumbers),'->',integer (y{MsgReceiver){ASNumbers
    line,' ',((y{MsgLink){::LinkNames),' ',prefix_text (y{MsgPrefix){AllPrefixes
)
write_lines =: 4 : 0
    text =. ''
    if. #y do.
        text =. (LF join y),LF
    end.
    text 1!:2 <'output/',x
)
