LF =: 10{a.
num =: 3 : ',''0'' 8!:2 y'
say =: 3 : '1!:2&2 y,LF'
words =: 3 : '(<;._1 '' '',y)-.<'''''
join =: 4 : '(#x)}.;(<x),&.>y'
fail =: 3 : 0
    Reason=:y
    throw.
)
kind =: 3 : '{.0{::y'
entry =: 4 : '(<,x),<y'
frac =: 3 : 0
    'p q'=.2 x:y
    if. q=1 do. num p else. (num p),'/',num q end.
)
valueText =: 3 : 0
    'p q'=.2 x:y
    scaled=.<.(1000000x*|p)%q
    tail=.num 1000000x|scaled
    sign=.''
    if. p<0 do. sign=.'-' end.
    (frac y),' (',sign,(num <.scaled%1000000x),'.',((6-#tail)#'0'),tail,')'
)
digits =: 3 : '(0<#y)*.*./y e.''0123456789'''
natural =: 3 : 0
    result=.0x
    for_c. y do. result=.(10*result)+'0123456789'i.c end.
    result
)
parseValue =: 3 : 0
    text=.y
    multiplier=.1r1
    if. 'meg'-:_3{.text do. multiplier=.1000000x
        text=._3}.text
    elseif. 'k'={:text do. multiplier=.1000x
        text=._1}.text
    elseif. 'm'={:text do. multiplier=.1r1000
        text=._1}.text
    elseif. 'u'={:text do. multiplier=.1r1000000
        text=._1}.text
    end.
    negative=.'-'={.text
    if. negative do. text=.}.text end.
    valid=.0
    if. digits text do. result=.natural text
        valid=.1
    else.
        positions=.I.text='.'
        if. 1=#positions do.
            at=.{.positions
            first=.at{.text
            second=.(>:at)}.text
            if. (digits first)*.digits second do.
                scale=.10x^#second
                result=.((scale*natural first)+natural second)%scale
                valid=.1
            end.
        end.
        if. -.valid do.
            positions=.I.text='/'
            if. 1=#positions do.
                at=.{.positions
                first=.at{.text
                second=.(>:at)}.text
                if. (digits first)*.digits second do.
                    bottom=.natural second
                    if. bottom~:0 do. result=.(natural first)%bottom
                        valid=.1 end.
                end.
            end.
        end.
    end.
    if. -.valid do. fail 'invalid value ',y end.
    result=.result*multiplier
    if. negative do. -result else. result end.
)
validNode =: 3 : 0
    if. y-:,'0' do. 1 return. end.
    if. (0=#y)+.8<#y do. 0 return. end.
    (({.y)e.'abcdefghijklmnopqrstuvwxyz')*.*./y e.'abcdefghijklmnopqrstuvwxyz0123456789'
)
terminals =: 3 : 0
    result=.1 2{y
    if. 0<#4{::y do. result=.result,4 5{y end.
    result
)
allNodes =: 4 : 0
    result=.0$a:
    for_item. y do. result=.result,terminals >item end.
    result=.~.result
    if. -.x do. result=.result-.<,'0' end.
    (/:result){result
)
reachable =: 4 : 0
    result=.,<,y
    cursor=.0
    while. cursor<#result do.
        current=.cursor{::result
        cursor=.>:cursor
        for_link. x do.
            'a b'=.>link
            if. a-:current do.
                if. -.(<b)e.result do. result=.result,<b end.
            end.
            if. b-:current do.
                if. -.(<a)e.result do. result=.result,<a end.
            end.
        end.
    end.
    result
)
floating =: 3 : 0
    links=.0$a:
    for_item. y do.
        item=.>item
        if. (kind item)e.'RVEH' do. links=.links,<1 2{item end.
    end.
    (0 allNodes y)-.links reachable '0'
)
voltageLoops =: 3 : 0
    result=.links=.0$a:
    for_item. y do.
        item=.>item
        if. (kind item)e.'VEH' do.
            if. (2{item)e.links reachable 1{::item do.
                result=.result,0{item
            end.
            links=.links,<1 2{item
        end.
    end.
    result
)
structure =: 3 : 0
    if. 0=#0 allNodes y do. fail 'no nodes' end.
    nodes=.floating y
    if. #nodes do. fail 'floating node ',0{::nodes end.
    loops=.voltageLoops y
    if. #loops do. fail 'voltage source loop at ',0{::loops end.
    i.0
)
gauss =: 4 : 0
    n=.#y
    rows=.x,.y
    for_k. i.n do.
        pivot=._1
        for_r. k+i.n-k do.
            if. 0~:(<r,k){rows do. pivot=.r
                break. end.
        end.
        if. pivot<0 do. 0$a: return. end.
        previous=.k{rows
        rows=.(pivot{rows)k}rows
        rows=.previous pivot}rows
        divisor=.(<k,k){rows
        rows=.((k{rows)%divisor)k}rows
        for_i. i.n do.
            factor=.(<i,k){rows
            if. (i~:k)*.factor~:0 do.
                rows=.((i{rows)-factor*k{rows)i}rows
            end.
        end.
    end.
    ,<n{"1 rows
)
addA =: 3 : 0
    'row col amount'=.y
    r=.Keys i.<row
    c=.Keys i.<col
    if. (r<#Keys)*.c<#Keys do.
        A=:(((<r,c){A)+amount)(<r,c)}A
    end.
    i.0
)
addB =: 3 : 0
    'key amount'=.y
    index=.Keys i.<key
    if. index<#Keys do. B=:((index{B)+amount)index}B end.
    i.0
)
sourceEntries =: 4 : 0
    if. 'I'=kind y do.
        (<(1{::y)entry -x),<(2{::y)entry x
    else. ,<(0{::y)entry x end.
)
build =: 3 : 0
    Nodes=:0 allNodes y
    Sources=:0$a:
    for_item. y do.
        item=.>item
        if. (kind item)e.'VEH' do. Sources=:Sources,<item end.
    end.
    Keys=:Nodes
    for_item. Sources do. Keys=:Keys,0{>item end.
    A=:(2##Keys)$0r1
    B=:(#Keys)$0r1
    for_item. y do.
        item=.>item
        'name a b w c d v'=.item
        k=.kind item
        if. k='R' do.
            g=.1r1%w
            addA (<a),(<a),<g
            addA (<b),(<b),<g
            addA (<a),(<b),<-g
            addA (<b),(<a),<-g
        elseif. k='G' do.
            addA (<a),(<c),<w
            addA (<b),(<d),<w
            addA (<a),(<d),<-w
            addA (<b),(<c),<-w
        elseif. k='F' do.
            addA (<a),(<v),<w
            addA (<b),(<v),<-w
        elseif. k e.'VEH' do.
            addA (<a),(<name),<1r1
            addA (<name),(<a),<1r1
            addA (<b),(<name),<_1r1
            addA (<name),(<b),<_1r1
            if. k='E' do.
                addA (<name),(<c),<-w
                addA (<name),(<d),<w
            elseif. k='H' do. addA (<name),(<v),<-w end.
        end.
        if. k e.'VI' do.
            for_entry. w sourceEntries item do. addB >entry end.
        end.
    end.
    i.0
)
column =: 3 : 0
    result=.(#Keys)$0r1
    for_entry. y do.
        'key amount'=.>entry
        index=.Keys i.<key
        if. index<#Keys do. result=.((index{result)+amount)index}result end.
    end.
    result
)
solve =: 3 : 0
    result=.A gauss y
    if. 0=#result do. fail 'singular matrix' end.
    0{::result
)
injection =: 3 : 0
    'a b'=.y
    solve column (<a entry 1r1),<b entry _1r1
)
voltage =: 4 : 0
    if. y-:,'0' do. 0r1 else. (Keys i.<,y){x end.
)
difference =: 4 : '(x voltage 0{::y)-x voltage 1{::y'
current =: 4 : 0
    'name a b w c d v'=.y
    select. kind y
    case. 'R' do. (x difference (<a),<b)%w
    case. 'I' do. w
    case. 'G' do. w*x difference (<c),<d
    case. 'F' do. w*(Keys i.<v){x
    case. do. (Keys i.<name){x
    end.
)
checkElement =: 3 : 0
    index=.ElementNames i.<,y
    if. index=#Elements do. fail 'unknown element ',y end.
    index
)
checkNode =: 3 : 0
    if. (-.y-:,'0')*.-.(<,y)e.0 allNodes Elements do.
        fail 'unknown node ',y
    end.
    i.0
)
addElement =: 3 : 0
    name=.0{::y
    k=.{.name
    if. -.k e.'RVIEGFH' do. fail 'unknown element type ',name end.
    count=.4
    if. k e.'EG' do. count=.6 elseif. k e.'FH' do. count=.5 end.
    if. count~:#y do. fail 'wrong field count for ',name end.
    if. (<name)e.ElementNames do. fail 'duplicate element ',name end.
    nodeCount=.2
    if. k e.'EG' do. nodeCount=.4 end.
    for_i. 1+i.nodeCount do.
        if. -.validNode i{::y do. fail 'invalid node ',i{::y end.
    end.
    v=.c=.d=.''
    if. k e.'FH' do.
        v=.3{::y
        index=.ElementNames i.<v
        if. index=#Elements do. fail 'unknown voltage source ',v end.
        if. 'V'~:kind index{::Elements do. fail 'unknown voltage source ',v end.
    elseif. k e.'EG' do. c=.3{::y
        d=.4{::y end.
    w=.parseValue >{:y
    if. (k='R')*.w<:0 do. fail 'nonpositive resistance ',name end.
    Elements=:Elements,<(<name),(1 2{y),(<w),(<c),(<d),<v
    ElementNames=:ElementNames,<name
    i.0
)
sensitivity =: 4 : 0
    'name a b w c d v'=.y
    k=.kind y
    if. k='R' do.
        amount=.(x current y)%w
        (<a entry amount),<b entry -amount
    elseif. k='I' do.
        (<a entry _1r1),<b entry 1r1
    elseif. k e.'GF' do.
        if. k='G' do. amount=.x difference (<c),<d
        else. amount=.(Keys i.<v){x end.
        (<a entry -amount),<b entry amount
    else.
        if. k='V' do. amount=.1r1
        elseif. k='E' do. amount=.x difference (<c),<d
        else. amount=.(Keys i.<v){x end.
        ,<name entry amount
    end.
)
reqEquivalent =: 3 : 0
    'a b'=.y
    wires=.0$a:
    for_item. Elements do.
        item=.>item
        if. 'V'=kind item do. wires=.wires,<1 2{item end.
    end.
    nodes=.(<,'0'),0 allNodes Elements
    grouped=.representatives=.0$a:
    for_node. nodes do.
        node=.>node
        if. -.(<node)e.grouped do.
            members=.wires reachable node
            grouped=.grouped,members
            representatives=.representatives,(#members)#<node
        end.
    end.
    first=.(grouped i.<a){::representatives
    second=.(grouped i.<b){::representatives
    if. first-:second do. ,<'Req = 0 (0.000000)' return. end.
    edges=.links=.0$a:
    for_item. Elements do.
        item=.>item
        if. 'R'=kind item do.
            p=.(grouped i.1{item){::representatives
            q=.(grouped i.2{item){::representatives
            if. -.p-:q do.
                edges=.edges,<(<p),(<q),<1r1%3{::item
                links=.links,<(<p),<q
            end.
        end.
    end.
    connected=.links reachable first
    if. -.(<second)e.connected do. ,<'Req = INFINITE' return. end.
    Keys=:connected-.<second
    Keys=:(/:Keys){Keys
    A=:(2##Keys)$0r1
    for_edge. edges do.
        'p q g'=.>edge
        if. (<p)e.connected do.
            addA (<p),(<p),<g
            addA (<q),(<q),<g
            addA (<p),(<q),<-g
            addA (<q),(<p),<-g
        end.
    end.
    rhs=.column ,<first entry 1r1
    result=.solve rhs
    ,<'Req = ',valueText (Keys i.<first){result
)
reduceNetwork =: 3 : 0
    'a b'=.y
    if. a-:b do. ,<'Req = 0 (0.000000)' return. end.
    items=.links=.0$a:
    for_item. Elements do.
        item=.>item
        if. 'R'=kind item do.
            items=.items,<4{.item
            links=.links,<1 2{item
        end.
    end.
    connected=.links reachable a
    if. -.(<b)e.connected do. ,<'Req = INFINITE' return. end.
    kept=.0$a:
    for_item. items do.
        if. (1{>item)e.connected do. kept=.kept,item end.
    end.
    items=.kept
    output=.0$a:
    serial=.0
    while. 1 do.
        removal=._1
        for_i. i.#items do.
            item=.i{::items
            if. (1{::item)-:2{::item do. removal=.i
                break. end.
        end.
        if. removal>:0 do.
            output=.output,<'remove ',0{::removal{::items
            items=.((i.#items)-.removal){items
            continue.
        end.
        ends=.0$a:
        for_item. items do. ends=.ends,1 2{>item end.
        nodes=.~.ends
        nodes=.(nodes-.<a)-.<b
        nodes=.(/:nodes){nodes
        for_node. nodes do.
            if. 1=+/ends e.node do.
                for_i. i.#items do.
                    if. node e.1 2{i{::items do. removal=.i
                        break. end.
                end.
                break.
            end.
        end.
        if. removal>:0 do.
            output=.output,<'remove ',0{::removal{::items
            items=.((i.#items)-.removal){items
            continue.
        end.
        first=.second=._1
        operation=.'||'
        for_i. i.#items do.
            xitem=.i{::items
            for_j. (>:i)+i.(#items)-(>:i) do.
                yitem=.j{::items
                pair=.1 2{xitem
                other=.1 2{yitem
                if. (pair-:other)+.pair-:|.other do.
                    first=.i
                    second=.j
                    break.
                end.
            end.
            if. first>:0 do. break. end.
        end.
        if. first>:0 do.
            xitem=.first{::items
            yitem=.second{::items
            p=.1{::xitem
            q=.2{::xitem
            xvalue=.3{::xitem
            yvalue=.3{::yitem
            resistance=.(xvalue*yvalue)%xvalue+yvalue
        else.
            operation=.'+'
            for_node. nodes do.
                if. 2~:+/ends e.node do. continue. end.
                touching=.i.0
                for_i. i.#items do.
                    if. node e.1 2{i{::items do. touching=.touching,i end.
                end.
                'first second'=.touching
                xitem=.first{::items
                yitem=.second{::items
                p=.1{::xitem
                if. node-:1{xitem do. p=.2{::xitem end.
                q=.1{::yitem
                if. node-:1{yitem do. q=.2{::yitem end.
                resistance=.(3{::xitem)+3{::yitem
                break.
            end.
        end.
        if. first<0 do. break. end.
        serial=.>:serial
        name=.'#',num serial
        output=.output,<name,' = ',(0{::xitem),' ',operation,' ',(0{::yitem),' = ',valueText resistance
        kept=.((i.#items)-.first,second){items
        items=.kept,<(<name),(<p),(<q),<resistance
    end.
    if. 1=#items do. output=.output,<'Req = ',valueText 3{::0{::items
    else. output=.output,<'not series-parallel: ',(num #items),' resistors remain' end.
    output
)
checkCircuit =: 3 : 0
    nodes=.0 allNodes Elements
    if. 0=#nodes do. ,<'no nodes' return. end.
    ends=.0$a:
    for_item. Elements do. ends=.ends,1 2{>item end.
    output=.0$a:
    for_node. nodes do.
        if. 2>+/ends e.node do. output=.output,<'dangling node ',>node end.
    end.
    for_node. floating Elements do. output=.output,<'floating node ',>node end.
    for_name. voltageLoops Elements do. output=.output,<'voltage source loop at ',>name end.
    if. 0=#output do.
        build Elements
        if. 0=#A gauss B do. output=.output,<'singular matrix' end.
    end.
    if. 0=#output do. ,<'ok' else. output end.
)
Commands =: words '.OP .CURRENT .VOLTAGE .POWER .KCL .THEVENIN .NORTON .MAXPOWER .TF .SENS .ZPARAM .SUPERPOSITION .SWEEP .MATRIX .REQ .REDUCE .CHECK .ALTER .DELETE .CLEAR .NODES .PRINT'
Counts =: 0 1 2 0 1 2 2 2 2 1 4 1 5 0 2 2 0 2 1 0 0 0
command =: 3 : 0
    name=.0{::y
    index=.Commands i.<name
    if. index=#Commands do. fail 'unknown command ',name end.
    if. (#y)~:1+index{Counts do. fail 'wrong argument count for ',name end.
    args=.}.y
    select. name
    case. '.ALTER' do.
        at=.checkElement 0{::args
        amount=.parseValue 1{::args
        item=.at{::Elements
        if. ('R'=kind item)*.amount<:0 do. fail 'nonpositive resistance ',0{::args end.
        text=.'altered ',(0{::args),': ',(frac 3{::item),' -> ',frac amount
        item=.(<amount)3}item
        Elements=:(<item)at}Elements
        ,<text return.
    case. '.DELETE' do.
        at=.checkElement 0{::args
        for_item. Elements do.
            item=.>item
            if. (6{::item)-:0{::args do. fail (0{::args),' is referenced by ',0{::item end.
        end.
        Elements=:((i.#Elements)-.at){Elements
        ElementNames=:((i.#ElementNames)-.at){ElementNames
        ,<'deleted ',0{::args return.
    case. '.CLEAR' do.
        text=.'cleared ',(num #Elements),' elements'
        Elements=:ElementNames=:0$a:
        ,<text return.
    case. '.NODES' do.
        if. 0=#Elements do. ,<'no nodes' return. end.
        output=.0$a:
        for_node. 1 allNodes Elements do.
            names=.0$a:
            for_item. Elements do.
                item=.>item
                if. node e.terminals item do. names=.names,0{item end.
            end.
            output=.output,<(>node),': ',' 'join names
        end.
        output return.
    case. '.PRINT' do.
        output=.0$a:
        for_item. Elements do.
            item=.>item
            fields=.(0{item),terminals item
            if. 0<#6{::item do. fields=.fields,6{item end.
            fields=.fields,<frac 3{::item
            output=.output,<' 'join fields
        end.
        if. 0=#output do. ,<'empty netlist' else. output end. return.
    case. '.CHECK' do. checkCircuit'' return.
    case. '.REQ';'.REDUCE' do.
        checkNode 0{::args
        checkNode 1{::args
        if. name-:'.REQ' do. reqEquivalent args else. reduceNetwork args end. return.
    case. '.SWEEP' do.
        at=.checkElement 0{::args
        first=.parseValue 1{::args
        last=.parseValue 2{::args
        step=.parseValue 3{::args
        checkNode 4{::args
        if. step<:0 do. fail 'invalid sweep step' end.
        if. first>last do. fail 'invalid sweep range' end.
        count=.1+<.(last-first)%step
        if. count>20 do. fail 'too many sweep points' end.
        item=.at{::Elements
        if. ('R'=kind item)*.first<:0 do. fail 'nonpositive resistance ',0{::args end.
        structure Elements
        output=.0$a:
        for_k. i.count do.
            amount=.first+k*step
            changed=.(<amount)3}item
            trial=.(<changed)at}Elements
            build trial
            text=.(0{::args),' = ',(frac amount),': '
            solved=.A gauss B
            if. 0=#solved do. text=.text,'singular matrix'
            else. text=.text,'V(',(4{::args),') = ',valueText (0{::solved)voltage 4{::args end.
            output=.output,<text
        end.
        output return.
    case. '.MATRIX' do.
        structure Elements
        build Elements
        labels=.0$a:
        for_node. Nodes do. labels=.labels,<'V(',(>node),')' end.
        for_item. Sources do. labels=.labels,<'I(',(0{::>item),')' end.
        output=.,<'unknowns: ',' 'join labels
        for_i. i.#Keys do.
            entries=.frac&.> <"0 i{A
            output=.output,<(i{::Keys),': ',(' 'join entries),' | ',frac i{B
        end.
        output return.
    end.
    if. name-:'.CURRENT' do. checkElement 0{::args
    elseif. name-:'.TF' do.
        checkNode 0{::args
        at=.checkElement 1{::args
        if. -.(kind at{::Elements)e.'VI' do. fail 'not an independent source ',1{::args end.
    else. for_node. args do. checkNode >node end.
    end.
    structure Elements
    build Elements
    solution=.solve B
    output=.0$a:
    select. name
    case. '.OP' do.
        for_node. Nodes do.
            output=.output,<'V(',(>node),') = ',valueText solution voltage >node
        end.
        for_item. Sources do.
            item=.>item
            output=.output,<'I(',(0{::item),') = ',valueText (Keys i.0{item){solution
        end.
    case. '.CURRENT' do.
        item=.(checkElement 0{::args){::Elements
        output=.,<'I(',(0{::item),') = ',valueText solution current item
    case. '.VOLTAGE' do.
        output=.,<'V(',(','join args),') = ',valueText solution difference args
    case. '.POWER' do.
        absorbed=.delivered=.total=.0r1
        for_item. Elements do.
            item=.>item
            power=.(solution difference 1 2{item)*solution current item
            output=.output,<'P(',(0{::item),') = ',valueText power
            if. power>0 do. absorbed=.absorbed+power
            elseif. power<0 do. delivered=.delivered-power end.
            total=.total+power
        end.
        output=.output,(<'absorbed = ',valueText absorbed),(<'delivered = ',valueText delivered),<'total = ',valueText total
    case. '.KCL' do.
        total=.0r1
        node=.0{::args
        for_item. Elements do.
            item=.>item
            if. -.(<node)e.1 2{item do. continue. end.
            amount=.0r1
            if. -.(1{::item)-:2{::item do.
                amount=.solution current item
                if. node-:2{::item do. amount=.-amount end.
            end.
            output=.output,<'I(',(0{::item),') leaving ',node,' = ',valueText amount
            total=.total+amount
        end.
        output=.output,<'sum = ',valueText total
    case. '.THEVENIN';'.NORTON';'.MAXPOWER' do.
        vth=.solution difference args
        rth=.(injection args)difference args
        if. name-:'.THEVENIN' do.
            output=.(<'Vth = ',valueText vth),<'Rth = ',valueText rth
        elseif. name-:'.NORTON' do.
            if. rth=0 do. fail 'zero thevenin resistance' end.
            output=.(<'In = ',valueText vth%rth),<'Rn = ',valueText rth
        else.
            if. rth<:0 do. fail 'nonpositive thevenin resistance' end.
            output=.(<'RL = ',valueText rth),<'Pmax = ',valueText (vth*vth)%4*rth
        end.
    case. '.TF' do.
        item=.(checkElement 1{::args){::Elements
        unit=.solve column 1r1 sourceEntries item
        output=.,<'gain = ',valueText unit voltage 0{::args
        if. 'V'=kind item do.
            amount=.(Keys i.0{item){unit
            if. amount=0 do. output=.output,<'input resistance = INFINITE'
            else. output=.output,<'input resistance = ',valueText _1r1%amount end.
        else. output=.output,<'input resistance = ',valueText unit difference 2 1{item end.
        injected=.injection (0{args),<,'0'
        output=.output,<'output resistance = ',valueText injected voltage 0{::args
    case. '.SENS' do.
        for_item. Elements do.
            item=.>item
            derivative=.solve column solution sensitivity item
            output=.output,<'dV(',(0{::args),')/d',(0{::item),' = ',valueText derivative voltage 0{::args
        end.
    case. '.ZPARAM' do.
        first=.injection 0 1{args
        second=.injection 2 3{args
        output=.(<'z11 = ',valueText first difference 0 1{args),(<'z12 = ',valueText second difference 0 1{args),(<'z21 = ',valueText first difference 2 3{args),<'z22 = ',valueText second difference 2 3{args
    case. '.SUPERPOSITION' do.
        total=.0r1
        for_item. Elements do.
            item=.>item
            if. (kind item)e.'VI' do.
                alone=.solve column (3{::item)sourceEntries item
                amount=.alone voltage 0{::args
                output=.output,<(0{::item),': V(',(0{::args),') = ',valueText amount
                total=.total+amount
            end.
        end.
        output=.output,<'total: V(',(0{::args),') = ',valueText total
    end.
    output
)
run =: 3 : 0
    Elements=:ElementNames=:0$a:
    lines=.<;._2 (1!:1<'/dev/stdin'),LF
    lineNumber=.0
    for_line. lines do.
        line=.>line
        lineNumber=.>:lineNumber
        if. line-:'.END' do. break. end.
        if. '*'={.line do. continue. end.
        try.
            tokens=.words line
            if. '.'={.line do.
                output=.command tokens
                for_text. output do. say >text end.
            else. addElement tokens end.
        catcht. say 'error: line ',(num lineNumber),': ',Reason
        end.
    end.
    i.0
)
run''
