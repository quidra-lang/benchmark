document_tree =: 4 : 0
    'kind value children forced mode' =. y{::Documents
    prefix =. (2*x)$' '
    if. kind-:'concat' do.
        lines =. 0$a:
        for_child. children do. lines =. lines,x document_tree child end.
        lines return.
    end.
    select. kind
    case. 'text';'suffix' do. line =. kind,' "',value,'"'
    case. 'if_break' do. line =. 'if_break "',(0{::value),'" "',(1{::value),'"'
    case. 'group' do. line =. 'group ',mode
    case. 'nest' do. line =. 'nest ',integer value
    case. do. line =. kind
    end.
    lines =. <prefix,line
    for_child. children do.
        lines =. lines,(x+1)document_tree child
    end.
    lines
)
line_diff =: 4 : 0
    old =. x
    new =. y
    n =. #old
    m =. #new
    lcs =. ((n+1),(m+1))$0
    for_i. |.i.n do.
        for_j. |.i.m do.
            if. (i{::old)-:j{::new do.
                value =. 1+(<(i+1),j+1){lcs
            else.
                value =. ((<(i+1),j){lcs)>.(<i,j+1){lcs
            end.
            lcs =. value(<i,j)}lcs
        end.
    end.
    i =. j =. deleted =. inserted =. 0
    hunks =. 0$a:
    current =. 0$a:
    start_old =. start_new =. removes =. adds =. 0
    while. (i<n)+.j<m do.
        common =. 0
        if. (i<n)*.j<m do. common =. (i{::old)-:j{::new end.
        if. common do.
            if. #current do.
                hunks =. hunks,<(<start_old),(<start_new),(<removes),(<adds),<current
                current =. 0$a:
            end.
            i =. i+1
            j =. j+1
            continue.
        end.
        if. 0=#current do.
            start_old =. i
            start_new =. j
            removes =. adds =. 0
        end.
        remove =. j=m
        if. (j<m)*.i<n do.
            remove =. ((<(i+1),j){lcs)>:(<i,j+1){lcs
        end.
        if. remove do.
            current =. current,<'-',i{::old
            removes =. removes+1
            deleted =. deleted+1
            i =. i+1
        else.
            current =. current,<'+',j{::new
            adds =. adds+1
            inserted =. inserted+1
            j =. j+1
        end.
    end.
    if. #current do.
        hunks =. hunks,<(<start_old),(<start_new),(<removes),(<adds),<current
    end.
    header =. 'hunks=',(integer #hunks),' deleted=',(integer deleted),' inserted=',integer inserted
    lines =. <header
    for_hunk. hunks do.
        'first second removed added changes' =. >hunk
        first =. first+removed>0
        second =. second+added>0
        header =. '@@ -',(integer first),',',(integer removed),' +',(integer second),',',(integer added),' @@'
        lines =. lines,(<header),changes
    end.
    lines
)
