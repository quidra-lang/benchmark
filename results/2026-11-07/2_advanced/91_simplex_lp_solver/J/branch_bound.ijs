branch_search =: 3 : 0
    limit =. y
    stack =. ,<(<ModelLower),(<ModelUpper),(<0),(<0),(<'root'),<''
    solves =. lines =. 0$a:
    incumbent =. i.0
    objective =. ''
    incumbents =. pruned =. infeasible =. 0
    status =. ''
    while. #stack do.
        if. (#solves)=limit do.
            status =. 'NODE_LIMIT'
            break.
        end.
        'lower upper depth parent branch parent_value' =. _1{::stack
        stack =. }:stack
        number =. 1+#solves
        result =. solve_lp(<lower),(<upper),(<number),<LogLevel
        solves =. solves,<result
        'lp_status lp_objective solution form tableau unbounded w p1 p2 drives redundant pivots logs' =. result
        if. lp_status-:'INFEASIBLE' do.
            outcome =. 'infeasible'
            infeasible =. infeasible+1
        elseif. lp_status-:'UNBOUNDED' do.
            outcome =. 'unbounded'
            status =. 'UNBOUNDED'
        else.
            prune =. 0
            if. finite objective do.
                if. ModelDirection-:'maximize' do.
                    prune =. lp_objective<:objective
                else.
                    prune =. lp_objective>:objective
                end.
            end.
            if. prune do.
                outcome =. 'pruned'
                pruned =. pruned+1
            else.
                fractional =. I.ModelInteger*.solution~:<.solution
                if. 0=#fractional do.
                    incumbent =. solution
                    objective =. lp_objective
                    outcome =. 'incumbent'
                    incumbents =. incumbents+1
                else.
                    variable =. {.fractional
                    value =. variable{solution
                    name =. variable{::ModelVariables
                    down =. <.value
                    up =. >.value
                    upper_child =. (<down)variable}upper
                    lower_child =. (<up)variable}lower
                    first =. (<lower_child),(<upper),(<depth+1),(<number),(<name,'>=',integer up),<lp_objective
                    second =. (<lower),(<upper_child),(<depth+1),(<number),(<name,'<=',integer down),<lp_objective
                    stack =. stack,(<first),<second
                    outcome =. 'branch ',name,' ',fraction value
                end.
            end.
        end.
        shown_parent =. ,'-'
        if. parent do. shown_parent =. integer parent end.
        shown_lp =. fraction lp_objective
        if. lp_status-:'INFEASIBLE' do. shown_lp =. 'infeasible' end.
        if. lp_status-:'UNBOUNDED' do. shown_lp =. 'unbounded' end.
        line =. 'NODE ',(integer number),' depth ',(integer depth),' parent ',shown_parent,' branch ',branch
        lines =. lines,<line,' lp ',shown_lp,' pivots ',(integer pivots),' action ',outcome
        if. status-:'UNBOUNDED' do. break. end.
    end.
    if. 0=#status do.
        status =. 'INFEASIBLE'
        if. #incumbent do. status =. 'OPTIMAL' end.
    end.
    bound =. objective
    if. status-:'NODE_LIMIT' do.
        bounds =. 0$0x
        for_node. |.stack do.
            'lower upper depth parent branch parent_value' =. >node
            lines =. lines,<'OPEN parent ',(integer parent),' branch ',branch,' bound ',fraction parent_value
            bounds =. bounds,parent_value
        end.
        if. finite objective do. bounds =. bounds,objective end.
        if. ModelDirection-:'maximize' do. bound =. >./bounds else. bound =. <./bounds end.
    end.
    line =. 'RESULT ',status,' objective ',(fraction objective),' nodes ',(integer #solves),' incumbents ',integer incumbents
    line =. line,' pruned ',(integer pruned),' infeasible ',(integer infeasible),' open ',integer #stack
    lines =. lines,<line,' bound ',fraction bound
    (<status),(<objective),(<incumbent),(<solves),(<0{::solves),(<lines),<#solves
)
