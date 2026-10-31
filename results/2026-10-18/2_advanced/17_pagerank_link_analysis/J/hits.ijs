hits =: 4 : 0
    'nodes links iterations' =. y
    sources =. targets =. x$<0$0
    links =. (/:links){links
    for_edge. links do.
        'source target' =. edge
        sources =. (<(target{::sources),source) target}sources
        targets =. (<(source{::targets),target) source}targets
    end.
    authority =. hub =. x$0.0
    authority =. 1.0 nodes}authority
    hub =. 1.0 nodes}hub
    for_step. i.iterations do.
        incoming =. outgoing =. x$0.0
        for_node. nodes do.
            incoming =. (ordered_sum (node{::sources){hub) node}incoming
        end.
        for_node. nodes do.
            outgoing =. (ordered_sum (node{::targets){incoming) node}outgoing
        end.
        na =. %:ordered_sum *:nodes{incoming
        nh =. %:ordered_sum *:nodes{outgoing
        authority =. ((nodes{incoming)%na) nodes}authority
        hub =. ((nodes{outgoing)%nh) nodes}hub
    end.
    (<authority),<hub
)
