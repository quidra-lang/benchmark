try_order =: 3 : 0
    restrictions =. empty_prohibitions ''
    paths =. NumberAgents$<i.0
    attempts =. 0$a:
    for_agent. y do.
        arguments =. (<agent),(<agent{Starts),(<0),(<restrictions),(<Horizon),<0
        'status path expanded' =. low_search arguments
        if. status=_1 do.
            (<0$a:),(<attempts),<_2 return.
        end.
        attempts =. attempts,<( <agent),(<status),(<path),<expanded
        if. status=0 do.
            (<0$a:),(<attempts),<agent return.
        end.
        paths =. (<path)agent}paths
        restrictions =. restrictions reserve_path(<path),(<0),<1
    end.
    (<paths),(<attempts),<_1
)
