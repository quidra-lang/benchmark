ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
div =: 4 : '_1 x:<.(x:x)%x:y'
num =: 3 : '10#.Digits i.y'
number =: 3 : 0
    if. y<0 do. '-',number -y return. end.
    text =. ''
    while. y>0 do.
        text =. ((10|y){Digits),text
        y =. y div 10
    end.
    if. #text do. text else. '0' end.
)
pad2 =: 3 : '_2{.''00'',number y'
split =: 4 : 0
    parts =. 0$a:
    while. 1 do.
        position =. y i.x
        parts =. parts,<position{.y
        if. position=#y do. parts return. end.
        y =. (position+1)}.y
    end.
)
join =: 4 : 0
    text =. ''
    for_index. i.#y do.
        if. index do. text =. text,x end.
        text =. text,index{::y
    end.
    text
)
read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
read_rows =: 3 : 0
    lines =. }.read_lines y
    rows =. 0$a:
    for_index. i.#lines do. rows =. rows,<(<index+2),<',' split index{::lines end.
    rows
)
empty_table =: 3 : '0 2$a:'
table_keys =: 3 : '0{"1 y'
has_key =: 4 : '(<x)e.table_keys y'
get_key =: 4 : '((table_keys y)i.<x){::1{"1 y'
put_key =: 4 : 0
    'key value' =. x
    position =. (table_keys y)i.<key
    if. position<#y do. (<value) (<position,1)}y
    else. y,1 2$(<key),<value end.
)
record =: 4 : '('' '' split x),.y'
sort_records =: 4 : 0
    keys =. 0$a:
    for_box. y do. keys =. keys,<x get_key >box end.
    (/:keys){y
)
record_error =: 4 : 0
    'line reason' =. y
    Errors =: Errors,<x,' line ',(number line),': ',reason
    i.0
)
load SourceDirectory,'items.ijs'
load SourceDirectory,'bom.ijs'
load SourceDirectory,'lot_sizing.ijs'
load SourceDirectory,'capacity.ijs'
load SourceDirectory,'costing.ijs'
load SourceDirectory,'report.ijs'

DemandKinds =: ' ' split 'MPS ORDER DEPENDENT'
RootKinds =: ' ' split 'MPS ORDER SAFETY'
SupplyKinds =: ' ' split 'STOCK RECEIPT ORDER'
MessageKinds =: ' ' split 'BELOW_SAFETY PAST_DUE RELEASE EXPEDITE DEFER CANCEL NO_ROUTING NO_DEMAND OVERLOAD'
new_demand =: 3 : '''item kind week quantity order_id line parent parent_number'' record y'
read_params =: 3 : 0
    for_box. read_lines 'params.txt' do.
        words =. ' ' split >box
        select. 0{::words
        case. 'horizon' do. Horizon =: num 1{::words
        case. 'peg' do. PegItems =: }.words
        case. 'tree_quantity' do. TreeQuantity =: num 1{::words
        end.
    end.
    Weeks =: >:i.Horizon
    i.0
)
schedule_error =: 3 : 0
    'id week quantity' =. y
    if. -.id has_key Items do. 'unknown item ',id
    elseif. (week<1)+.week>Horizon do. 'week ',(number week),' outside horizon'
    elseif. quantity<1 do. 'bad quantity ',number quantity
    else. '' end.
)
read_schedule =: 3 : 0
    rows =. seen =. 0$a:
    for_box. read_rows y do.
        'line fields' =. >box
        id =. 0{::fields
        week =. num 1{::fields
        quantity =. num 2{::fields
        key =. id,'/',number week
        reason =. schedule_error (<id),(<week),<quantity
        if. (0=#reason)*.y-:'mps.csv' do.
            if. (<key)e.seen do. reason =. 'duplicate ',id,' week ',number week end.
        end.
        if. #reason do. y record_error (<line),<reason
        else.
            row =. 'item week quantity line' record (<id),(<week),(<quantity),<line
            rows =. rows,<row
            seen =. seen,<key
        end.
    end.
    rows
)
read_inquiries =: 3 : 0
    Inquiries =: 0$a:
    seen =. 0$a:
    for_box. read_rows 'orders.csv' do.
        'line fields' =. >box
        'id item quantitytext weektext' =. fields
        quantity =. num quantitytext
        week =. num weektext
        if. (<id)e.seen do. reason =. 'duplicate order ',id
        else. reason =. schedule_error (<item),(<week),<quantity end.
        if. #reason do. 'orders.csv' record_error (<line),<reason
        else.
            inquiry =. 'id item quantity week line' record (<id),(<item),(<quantity),(<week),<line
            Inquiries =: Inquiries,<inquiry
            seen =. seen,<id
        end.
    end.
    OrderIds =: /:~seen
    i.0
)
read_data =: 3 : 0
    Errors =: 0$a:
    read_params ''
    read_items ''
    ItemIds =: /:~table_keys Items
    read_bom ''
    read_workcenters ''
    read_routings ''
    mps =. read_schedule 'mps.csv'
    receipts =. read_schedule 'receipts.csv'
    read_inquiries ''
    MpsDemands =: 0$a:
    for_box. mps do.
        row =. >box
        values =. (<'item' get_key row),(<'MPS'),(<'week' get_key row),(<'quantity' get_key row),( <''),(<0),( <''),<0
        MpsDemands =: MpsDemands,<new_demand values
    end.
    analyze_bom ''
    Receipts =: Scheduled =: empty_table ''
    for_box. ItemIds do.
        Receipts =: (box,<0$a:) put_key Receipts
        Scheduled =: (box,<Horizon$0) put_key Scheduled
    end.
    keys =. 0 2$0
    for_box. receipts do.
        row =. >box
        keys =. keys,('week' get_key row),'line' get_key row
    end.
    for_box. (/:keys){receipts do.
        row =. >box
        id =. 'item' get_key row
        week =. ('week' get_key row)-1
        quantity =. 'quantity' get_key row
        Receipts =: ((<id),<(id get_key Receipts),box) put_key Receipts
        values =. id get_key Scheduled
        values =. (quantity+week{values) week}values
        Scheduled =: ((<id),<values) put_key Scheduled
    end.
    i.0
)
plan_item =: 3 : 0
    plan =. y
    item =. 'item' get_key plan
    id =. 'id' get_key item
    gross =. Horizon$0
    receipts =. 'receipts' get_key plan
    for_box. 'demands' get_key plan do.
        demand =. >box
        index =. ('week' get_key demand)-1
        gross =. (('quantity' get_key demand)+index{gross) index}gross
    end.
    projected =. 'on_hand' get_key item
    safety =. 'safety_stock' get_key item
    lead =. 'lead_time' get_key item
    onhand =. net =. plannedreceipts =. plannedreleases =. Horizon$0
    orders =. 0$a:
    for_week. i.Horizon do.
        available =. projected+(week{receipts)-week{gross
        projected =. available
        if. available<safety do.
            quantity =. item lot_size (<week),(<available),(<receipts),<gross
            original =. (week+1)-lead
            release =. 1>.original
            values =. (<id),(<1+#orders),(<week+1),(<quantity),(<original),<release
            orders =. orders,<'item number receipt quantity original_release release' record values
            net =. (safety-available) week}net
            plannedreceipts =. quantity week}plannedreceipts
            plannedreleases =. (quantity+(release-1){plannedreleases) (release-1)}plannedreleases
            projected =. available+quantity
        end.
        onhand =. projected week}onhand
    end.
    updates =. 'gross on_hand net planned_receipts planned_releases orders' record (<gross),(<onhand),(<net),(<plannedreceipts),(<plannedreleases),<orders
    for_row. updates do. plan =. row put_key plan end.
    plan
)
work_center_loads =: 3 : 0
    loads =. empty_table ''
    for_box. CenterIds do. loads =. (box,<Horizon$0) put_key loads end.
    for_idbox. PlanningOrder do.
        id =. >idbox
        operations =. id get_key Routings
        lead =. 'lead_time' get_key id get_key Items
        for_orderbox. 'orders' get_key id get_key y do.
            order =. >orderbox
            for_index. i.#operations do.
                operation =. index{::operations
                center =. 'center' get_key operation
                week =. operation_week ('receipt' get_key order),lead,index,#operations
                time =. operation operation_minutes 'quantity' get_key order
                values =. center get_key loads
                values =. (time+(week-1){values) (week-1)}values
                loads =. ((<center),<values) put_key loads
            end.
        end.
    end.
    loads
)
run_mrp =: 3 : 0
    plans =. empty_table ''
    for_box. PlanningOrder do.
        id =. >box
        values =. (<id get_key Items),(<id get_key Scheduled),(<0$a:),(<Horizon$0),(<Horizon$0),(<Horizon$0),(<Horizon$0),(<Horizon$0),<0$a:
        plan =. 'item receipts demands gross on_hand net planned_receipts planned_releases orders' record values
        plans =. ((<id),<plan) put_key plans
    end.
    for_box. MpsDemands,y do.
        demand =. >box
        id =. 'item' get_key demand
        plan =. id get_key plans
        plan =. ((<'demands'),<('demands' get_key plan),box) put_key plan
        plans =. ((<id),<plan) put_key plans
    end.
    for_box. PlanningOrder do.
        id =. >box
        plan =. plan_item id get_key plans
        plans =. ((<id),<plan) put_key plans
        for_orderbox. 'orders' get_key plan do.
            order =. >orderbox
            for_rowbox. id get_key Children do.
                row =. >rowbox
                child =. 'child' get_key row
                values =. (<child),(<'DEPENDENT'),(<'release' get_key order),(<row need 'quantity' get_key order),( <''),(<0),(<id),<'number' get_key order
                demand =. new_demand values
                childplan =. child get_key plans
                childplan =. ((<'demands'),<('demands' get_key childplan),<demand) put_key childplan
                plans =. ((<child),<childplan) put_key plans
            end.
        end.
    end.
    loads =. work_center_loads plans
    overloads =. empty_table ''
    for_box. CenterIds do.
        id =. >box
        available =. 'available' get_key id get_key Centers
        overloads =. ((<id),<0>.(id get_key loads)-available) put_key overloads
    end.
    'items loads overloads' record (<plans),(<loads),<overloads
)
past_due_quantity =: 3 : 0
    quantity =. 0
    for_box. 'orders' get_key y do.
        order =. >box
        if. ('original_release' get_key order)<1 do. quantity =. quantity+'quantity' get_key order end.
    end.
    quantity
)
material_reason =: 4 : 0
    for_box. PlanningOrder do.
        id =. >box
        trial =. past_due_quantity id get_key 'items' get_key y
        current =. past_due_quantity id get_key 'items' get_key x
        if. trial>current do. id return. end.
    end.
    ''
)
capacity_reason =: 4 : 0
    for_box. CenterIds do.
        id =. >box
        trial =. id get_key 'overloads' get_key y
        current =. id get_key 'overloads' get_key x
        found =. I.trial>current
        if. #found do. id,' week ',number 1+{.found return. end.
    end.
    ''
)
promise_inquiries =: 3 : 0
    current =. y
    promised =. promises =. 0$a:
    for_box. Inquiries do.
        inquiry =. >box
        requested =. 'week' get_key inquiry
        promisedweek =. materialweek =. 0
        firstreason =. ''
        for_week. requested+i.1+Horizon-requested do.
            values =. (<'item' get_key inquiry),(<'ORDER'),(<week),(<'quantity' get_key inquiry),(<'id' get_key inquiry),(<'line' get_key inquiry),( <''),<0
            demand =. new_demand values
            trial =. run_mrp promised,<demand
            reason =. current material_reason trial
            if. 0=#reason do.
                if. materialweek=0 do. materialweek =. week end.
                reason =. current capacity_reason trial
            end.
            if. 0=#reason do.
                promisedweek =. week
                promised =. promised,<demand
                current =. trial
                break.
            end.
            if. week=requested do. firstreason =. reason end.
        end.
        promise =. 'inquiry week material_week reason' record (<inquiry),(<promisedweek),(<materialweek),<firstreason
        promises =. promises,<promise
    end.
    (<promises),<current
)
parent_supply =: 4 : 0
    plan =. ('parent' get_key y) get_key x
    indices =. 'order_supply_indices' get_key plan
    index =. (('parent_number' get_key y)-1){indices
    index{::'supplies' get_key plan
)
sort_demands =: 3 : 0
    keys =. 0 5$0
    for_box. y do.
        demand =. >box
        key =. ('week' get_key demand),(DemandKinds i.<'kind' get_key demand),('line' get_key demand),(ItemIds i.<'parent' get_key demand),'parent_number' get_key demand
        keys =. keys,key
    end.
    (/:keys){y
)
sorted_roots =: 3 : 0
    roots =. 0$a:
    keys =. 0$a:
    sortkeys =. 0 4$0
    for_box. y do.
        root =. >box
        key =. (<'item' get_key root),(<'kind' get_key root),(<'week' get_key root),<'order_id' get_key root
        if. (<key)e.keys do. continue. end.
        keys =. keys,<key
        roots =. roots,box
        numeric =. (ItemIds i.<'item' get_key root),(RootKinds i.<'kind' get_key root),('week' get_key root),OrderIds i.<'order_id' get_key root
        sortkeys =. sortkeys,numeric
    end.
    (/:sortkeys){roots
)
new_supply =: 3 : 0
    'kind week quantity line order' =. y
    'kind week quantity line order remaining allocations roots' record (<kind),(<week),(<quantity),(<line),(<order),(<quantity),(<0$a:),<0$a:
)
peg_plan =: 3 : 0
    plan =. y
    plans =. 'items' get_key plan
    for_idbox. PlanningOrder do.
        id =. >idbox
        itemplan =. id get_key plans
        item =. 'item' get_key itemplan
        demands =. sort_demands 'demands' get_key itemplan
        safety =. 'safety_stock' get_key item
        if. safety>0 do.
            demand =. new_demand (<id),(<'SAFETY'),(<0),(<safety),( <''),(<0),( <''),<0
            demands =. (<demand),demands
        end.
        supplies =. 0$a:
        if. ('on_hand' get_key item)>0 do.
            supplies =. supplies,<new_supply (<'STOCK'),(<0),(<'on_hand' get_key item),(<0),<empty_table ''
        end.
        for_box. id get_key Receipts do.
            receipt =. >box
            supplies =. supplies,<new_supply (<'RECEIPT'),(<'week' get_key receipt),(<'quantity' get_key receipt),(<'line' get_key receipt),<empty_table ''
        end.
        for_box. 'orders' get_key itemplan do.
            order =. >box
            supplies =. supplies,<new_supply (<'ORDER'),(<'receipt' get_key order),(<'quantity' get_key order),(<0),<order
        end.
        keys =. 0 3$0
        for_box. supplies do.
            supply =. >box
            keys =. keys,('week' get_key supply),(SupplyKinds i.<'kind' get_key supply),'line' get_key supply
        end.
        supplies =. (/:keys){supplies
        index =. 0
        for_box. demands do.
            demand =. >box
            remaining =. 'quantity' get_key demand
            while. remaining>0 do.
                while. 0='remaining' get_key index{::supplies do. index =. index+1 end.
                supply =. index{::supplies
                share =. remaining<.'remaining' get_key supply
                allocation =. 'demand share' record (<demand),<share
                supply =. ((<'allocations'),<('allocations' get_key supply),<allocation) put_key supply
                supply =. ((<'remaining'),<('remaining' get_key supply)-share) put_key supply
                supplies =. (<supply) index}supplies
                remaining =. remaining-share
            end.
        end.
        orderindices =. 0$0
        for_index. i.#supplies do.
            supply =. index{::supplies
            if. -.'ORDER'-:'kind' get_key supply do. continue. end.
            orderindices =. orderindices,index
            roots =. 0$a:
            for_box. 'allocations' get_key supply do.
                demand =. 'demand' get_key >box
                if. 'DEPENDENT'-:'kind' get_key demand do. roots =. roots,'roots' get_key plans parent_supply demand
                else. roots =. roots,<demand end.
            end.
            supply =. ((<'roots'),<sorted_roots roots) put_key supply
            supplies =. (<supply) index}supplies
        end.
        itemplan =. ((<'supplies'),<supplies) put_key itemplan
        itemplan =. ((<'order_supply_indices'),<orderindices) put_key itemplan
        plans =. ((<id),<itemplan) put_key plans
    end.
    ((<'items'),<plans) put_key plan
)
demand_text =: 3 : 0
    kind =. 'kind' get_key y
    id =. 'item' get_key y
    if. kind-:'SAFETY' do. 'SAFETY ',id
    elseif. kind-:'MPS' do. 'MPS ',id,' week ',number 'week' get_key y
    elseif. kind-:'ORDER' do. 'ORDER ',('order_id' get_key y),' ',id,' week ',number 'week' get_key y
    else. ('parent' get_key y),' order ',(number 'parent_number' get_key y),' week ',number 'week' get_key y end.
)
supply_header =: 3 : 0
    kind =. 'kind' get_key y
    if. kind-:'STOCK' do. 'STOCK quantity ',number 'quantity' get_key y
    elseif. kind-:'RECEIPT' do. 'RECEIPT line ',(number 'line' get_key y),' week ',(number 'week' get_key y),' quantity ',number 'quantity' get_key y
    else.
        order =. 'order' get_key y
        'ORDER ',(number 'number' get_key order),' receipt ',(number 'receipt' get_key order),' release ',(number 'release' get_key order),' quantity ',number 'quantity' get_key order
    end.
)
depth_label =: 3 : '(y#''.''),number y'
grid_lines =: 3 : 0
    plans =. 'items' get_key y
    lines =. 0$a:
    for_idbox. PlanningOrder do.
        id =. >idbox
        plan =. id get_key plans
        item =. 'item' get_key plan
        text =. 'ITEM ',id,' LLC ',(number id get_key LowCodes),' LT ',number 'lead_time' get_key item
        text =. text,' LOT ',(lot_label item),' SS ',(number 'safety_stock' get_key item),' OH ',(number 'on_hand' get_key item),' ','description' get_key item
        lines =. lines,<text
        lines =. lines,<'WEEK' table_row (<Weeks),<6
        labels =. ' ' split 'GROSS RECEIPTS ON_HAND NET PLAN_RCPT PLAN_REL'
        fields =. ' ' split 'gross receipts on_hand net planned_receipts planned_releases'
        for_index. i.#labels do. lines =. lines,<(index{::labels) table_row (<(index{::fields) get_key plan),<6 end.
        text =. 'TOTAL gross ',(number +/'gross' get_key plan),' receipts ',number +/'receipts' get_key plan
        text =. text,' planned ',(number +/'planned_receipts' get_key plan),' orders ',(number #'orders' get_key plan),' ending ',number {:'on_hand' get_key plan
        lines =. lines,<text
    end.
    lines
)
where_used_lines =: 3 : 0
    'id depth extension' =. y
    lines =. 0$a:
    for_box. id get_key Parents do.
        row =. >box
        parent =. 'parent' get_key row
        cumulative =. extension*'qty_per' get_key row
        lines =. lines,<(depth_label depth),' ',parent,' qty ',(number 'qty_per' get_key row),' ext ',number cumulative
        lines =. lines,where_used_lines (<parent),(<depth+1),<cumulative
    end.
    lines
)
allocation_lines =: 4 : 0
    'supply depth' =. y
    lines =. 0$a:
    for_box. 'allocations' get_key supply do.
        allocation =. >box
        demand =. 'demand' get_key allocation
        lines =. lines,<((2*depth)#' '),'ALLOC ',(number 'share' get_key allocation),' ',demand_text demand
        if. ('ORDER'-:'kind' get_key supply)*.'DEPENDENT'-:'kind' get_key demand do.
            parent =. x parent_supply demand
            lines =. lines,x allocation_lines (<parent),<depth+1
        end.
    end.
    lines
)
pegging_lines =: 3 : 0
    plans =. 'items' get_key y
    lines =. 0$a:
    for_idbox. PegItems do.
        id =. >idbox
        plan =. id get_key plans
        lines =. lines,<'PEG ',id,' orders ',number #'orders' get_key plan
        lines =. lines,where_used_lines (<id),(<1),<1
        for_kindbox. SupplyKinds do.
            kind =. >kindbox
            for_box. 'supplies' get_key plan do.
                supply =. >box
                if. -.kind-:'kind' get_key supply do. continue. end.
                lines =. lines,<supply_header supply
                lines =. lines,plans allocation_lines (<supply),<1
                excess =. 'remaining' get_key supply
                if. excess>0 do. lines =. lines,<'  EXCESS ',number excess end.
                for_rootbox. 'roots' get_key supply do. lines =. lines,<'  ROOT ',demand_text >rootbox end.
            end.
        end.
    end.
    lines
)
explode_tree =: 3 : 0
    'id gross extension depth' =. y
    for_box. id get_key Children do.
        row =. >box
        child =. 'child' get_key row
        item =. child get_key Items
        cumulative =. extension*'qty_per' get_key row
        quantity =. row need gross
        total =. 0
        if. child has_key TreeTotals do. total =. child get_key TreeTotals end.
        TreeTotals =: ((<child),<total+quantity) put_key TreeTotals
        text =. (depth_label depth),' ',child,' qty ',(number 'qty_per' get_key row),' scrap ',number 'scrap' get_key row
        text =. text,' ext ',(number cumulative),' gross ',(number quantity),' lt ',number 'lead_time' get_key item
        text =. text,' cum ',(number child get_key Cumulative),' ','description' get_key item
        TreeOutput =: TreeOutput,<text
        explode_tree (<child),(<quantity),(<cumulative),<depth+1
    end.
    i.0
)
bom_tree_lines =: 3 : 0
    lines =. 0$a:
    for_idbox. ItemIds do.
        id =. >idbox
        if. (0=#id get_key Children)+.0<#id get_key Parents do. continue. end.
        item =. id get_key Items
        lines =. lines,<'TREE ',id,' quantity ',number TreeQuantity
        text =. '0 ',id,' ext 1 gross ',(number TreeQuantity),' lt ',number 'lead_time' get_key item
        lines =. lines,<text,' cum ',(number id get_key Cumulative),' ','description' get_key item
        TreeTotals =: empty_table ''
        TreeOutput =: 0$a:
        explode_tree (<id),(<TreeQuantity),(<1),<1
        lines =. lines,TreeOutput
        for_childbox. /:~table_keys TreeTotals do.
            child =. >childbox
            lines =. lines,<'SUM ',child,' ',number child get_key TreeTotals
        end.
        path =. <id
        current =. id
        while. #current get_key Children do.
            best =. _1
            chosen =. ''
            for_box. current get_key Children do.
                child =. 'child' get_key >box
                lead =. child get_key Cumulative
                if. lead>best do. best =. lead
                chosen =. child end.
            end.
            current =. chosen
            path =. path,<current
        end.
        lines =. lines,<'CRITICAL ',(' -> ' join path),' cum ',number id get_key Cumulative
    end.
    lines
)
cost_lines =: 3 : 0
    plans =. 'items' get_key y
    usages =. values =. empty_table ''
    for_box. ItemIds do.
        id =. >box
        usage =. +/'gross' get_key id get_key plans
        value =. usage*'total' get_key id get_key Costs
        usages =. ((<id),<usage) put_key usages
        values =. ((<id),<value) put_key values
    end.
    classes =. abc_classes values
    lines =. <'item,material,labor,total,usage,value,class'
    for_box. ItemIds do.
        id =. >box
        cost =. id get_key Costs
        parts =. (<id),(<money 'material' get_key cost),(<money 'labor' get_key cost),<money 'total' get_key cost
        parts =. parts,(<number id get_key usages),(<money id get_key values),<id get_key classes
        lines =. lines,<',' join parts
    end.
    lines
)
exception_lines =: 3 : 0
    plans =. 'items' get_key y
    messages =. 0$a:
    for_idbox. PlanningOrder do.
        id =. >idbox
        plan =. id get_key plans
        item =. 'item' get_key plan
        onhand =. 'on_hand' get_key item
        safety =. 'safety_stock' get_key item
        if. onhand<safety do. messages =. messages,<'BELOW_SAFETY ',id,' on hand ',(number onhand),' safety ',number safety end.
        for_box. 'orders' get_key plan do.
            order =. >box
            original =. 'original_release' get_key order
            detail =. id,' order ',(number 'number' get_key order),' receipt ',number 'receipt' get_key order
            if. original<1 do.
                text =. 'PAST_DUE ',detail,' release ',(number original),' late ',(number 1-original),' quantity ',number 'quantity' get_key order
                messages =. messages,<text
            elseif. original=1 do. messages =. messages,<'RELEASE ',detail,' quantity ',number 'quantity' get_key order end.
        end.
        balances =. onhand-+/\'gross' get_key plan
        covered =. 0
        for_box. id get_key Receipts do.
            receipt =. >box
            found =. I.(balances+covered)<safety
            needweek =. 0
            if. #found do. needweek =. 1+{.found end.
            week =. 'week' get_key receipt
            quantity =. 'quantity' get_key receipt
            detail =. id,' receipt line ',(number 'line' get_key receipt),' week ',(number week),' quantity ',number quantity
            if. needweek=0 do. messages =. messages,<'CANCEL ',detail
            elseif. needweek<week do. messages =. messages,<'EXPEDITE ',detail,' to ',number needweek
            elseif. needweek>week do. messages =. messages,<'DEFER ',detail,' to ',number needweek end.
            covered =. covered+quantity
        end.
        if. (0<#id get_key Children)*.0=#id get_key Routings do. messages =. messages,<'NO_ROUTING ',id end.
        if. (0=+/'gross' get_key plan)*.onhand>0 do. messages =. messages,<'NO_DEMAND ',id,' on hand ',number onhand end.
    end.
    for_idbox. CenterIds do.
        id =. >idbox
        loads =. id get_key 'loads' get_key y
        overloads =. id get_key 'overloads' get_key y
        available =. 'available' get_key id get_key Centers
        for_week. I.overloads>0 do.
            messages =. messages,<'OVERLOAD ',id,' week ',(number week+1),' load ',(number week{loads),' available ',number available
        end.
    end.
    lines =. 0$a:
    for_box. Errors do. lines =. lines,<'ERROR ',>box end.
    summary =. 'SUMMARY errors ',number #Errors
    for_kindbox. MessageKinds do.
        kind =. >kindbox
        count =. 0
        for_box. messages do.
            if. kind-:0{::' ' split >box do. count =. count+1 end.
        end.
        summary =. summary,' ',(tolower kind),' ',number count
    end.
    lines,messages,<summary
)
capacity_lines =: 3 : 0
    lines =. 0$a:
    totals =. empty_table ''
    for_idbox. CenterIds do.
        id =. >idbox
        center =. id get_key Centers
        available =. 'available' get_key center
        loads =. id get_key 'loads' get_key y
        overloads =. id get_key 'overloads' get_key y
        leveled =. available level_loads loads
        total =. +/loads
        totals =. ((<id),<total) put_key totals
        peak =. 0
        if. total>0 do. peak =. 1+loads i.>./loads end.
        text =. 'CENTER ',id,' minutes ',(number 'minutes' get_key center),' efficiency ',(number 'efficiency' get_key center),' available ',number available
        lines =. lines,<text,' ','description' get_key center
        lines =. lines,<'WEEK' table_row (<Weeks),<7
        lines =. lines,<'LOAD' table_row (<loads),<7
        lines =. lines,<'UTIL' table_row (<loads percent available),<7
        lines =. lines,<'OVER' table_row (<overloads),<7
        lines =. lines,<'LEVELED' table_row (<leveled),<7
        text =. 'TOTAL load ',(number total),' available ',(number available*Horizon),' utilization ',number total percent available*Horizon
        text =. text,' overloaded ',(number +/overloads>0),' peak ',(number peak),' backlog ',number 0>.({.leveled)-available
        lines =. lines,<text
    end.
    ranked =. 0$a:
    for_idbox. CenterIds do.
        id =. >idbox
        position =. #ranked
        for_index. i.#ranked do.
            other =. index{::ranked
            first =. (id get_key totals)*'available' get_key other get_key Centers
            second =. (other get_key totals)*'available' get_key id get_key Centers
            if. first>second do. position =. index
            break. end.
        end.
        ranked =. (position{.ranked),idbox,position}.ranked
    end.
    for_rank. i.#ranked do.
        id =. rank{::ranked
        total =. id get_key totals
        available =. Horizon*'available' get_key id get_key Centers
        lines =. lines,<'RANK ',(number rank+1),' ',id,' load ',(number total),' utilization ',number total percent available
    end.
    lines
)
promise_lines =: 3 : 0
    'promises base final' =. y
    plans =. 'items' get_key final
    lines =. 0$a:
    counts =. 3$0
    for_box. promises do.
        promise =. >box
        inquiry =. 'inquiry' get_key promise
        id =. 'id' get_key inquiry
        requested =. 'week' get_key inquiry
        week =. 'week' get_key promise
        materialweek =. 'material_week' get_key promise
        reason =. 'reason' get_key promise
        head =. 'ORDER ',id,' ',('item' get_key inquiry),' quantity ',(number 'quantity' get_key inquiry),' requested ',number requested
        material =. 'none'
        if. materialweek>0 do. material =. number materialweek end.
        if. week=0 do.
            counts =. (1+2{counts) 2}counts
            lines =. lines,<head,' rejected material ',material,' reason ',reason
            continue.
        elseif. week=requested do.
            counts =. (1+0{counts) 0}counts
            lines =. lines,<head,' promised ',number week
        else.
            counts =. (1+1{counts) 1}counts
            lines =. lines,<head,' promised ',(number week),' late ',(number week-requested),' material ',material,' reason ',reason
        end.
        for_itembox. PlanningOrder do.
            itemid =. >itembox
            plan =. itemid get_key plans
            supplies =. 'supplies' get_key plan
            for_index. 'order_supply_indices' get_key plan do.
                supply =. index{::supplies
                serves =. 0
                for_rootbox. 'roots' get_key supply do.
                    root =. >rootbox
                    if. ('ORDER'-:'kind' get_key root)*.id-:'order_id' get_key root do. serves =. 1 end.
                end.
                if. serves do.
                    order =. 'order' get_key supply
                    text =. '  SUPPLY ',itemid,' order ',(number 'number' get_key order),' receipt ',number 'receipt' get_key order
                    lines =. lines,<text,' release ',(number 'release' get_key order),' quantity ',number 'quantity' get_key order
                end.
            end.
        end.
    end.
    for_idbox. PlanningOrder do.
        id =. >idbox
        before =. id get_key 'items' get_key base
        after =. id get_key plans
        old =. 'planned_receipts' get_key before
        new =. 'planned_receipts' get_key after
        changed =. I.old~:new
        if. #changed do.
            text =. 'CHANGE ',id,' from ',(number 1+{.changed),' planned ',(number +/old),' -> ',number +/new
            lines =. lines,<text,' orders ',(number #'orders' get_key before),' -> ',number #'orders' get_key after
        end.
    end.
    lines,<'SUMMARY orders ',(number #promises),' on_time ',(number 0{counts),' late ',(number 1{counts),' rejected ',number 2{counts
)
release_lines =: 3 : 0
    plans =. 'items' get_key y
    orders =. 0$a:
    keys =. 0 3$0
    available =. empty_table ''
    for_idbox. PlanningOrder do.
        id =. >idbox
        item =. id get_key Items
        available =. ((<id),<('on_hand' get_key item)+{.id get_key Scheduled) put_key available
        for_box. 'orders' get_key id get_key plans do.
            order =. >box
            if. 1='release' get_key order do.
                orders =. orders,box
                keys =. keys,('original_release' get_key order),(ItemIds i.<id),'number' get_key order
            end.
        end.
    end.
    orders =. (/:keys){orders
    made =. readycount =. bought =. purchase =. 0
    lines =. 0$a:
    for_box. orders do.
        order =. >box
        id =. 'item' get_key order
        item =. id get_key Items
        quantity =. 'quantity' get_key order
        original =. 'original_release' get_key order
        head =. id,' order ',(number 'number' get_key order),' receipt ',(number 'receipt' get_key order),' quantity ',number quantity
        if. original<1 do. head =. head,' late ',number 1-original end.
        rows =. id get_key Children
        if. 0=#rows do.
            value =. quantity*'material' get_key item
            purchase =. purchase+value
            bought =. bought+1
            lines =. lines,<'BUY ',head,' value ',money value
            continue.
        end.
        needs =. have =. 0$0
        for_rowbox. rows do.
            row =. >rowbox
            needs =. needs,row need quantity
            have =. have,('child' get_key row) get_key available
        end.
        ready =. *./needs<:have
        made =. made+1
        readycount =. readycount+ready
        status =. ready{::'SHORT';'READY'
        lines =. lines,<'MAKE ',head,' ',status
        for_index. i.#rows do.
            child =. 'child' get_key index{::rows
            requirement =. index{needs
            stock =. index{have
            text =. '  PICK ',child,' need ',(number requirement),' available ',(number stock),' short ',number 0>.requirement-stock
            lines =. lines,<text
            if. ready do. available =. ((<child),<stock-requirement) put_key available end.
        end.
        operations =. id get_key Routings
        for_index. i.#operations do.
            operation =. index{::operations
            week =. operation_week ('receipt' get_key order),('lead_time' get_key item),index,#operations
            text =. '  OPERATION ',(number 'number' get_key operation),' ',('center' get_key operation),' week ',number week
            lines =. lines,<text,' minutes ',number operation operation_minutes quantity
        end.
    end.
    lines,<'SUMMARY make ',(number made),' ready ',(number readycount),' short ',(number made-readycount),' buy ',(number bought),' value ',money purchase
)
value_plan_lines =: 3 : 0
    plans =. 'items' get_key y
    lines =. <'week,inventory,purchases,labor'
    for_week. i.Horizon do.
        inventory =. purchases =. labor =. 0
        for_idbox. PlanningOrder do.
            id =. >idbox
            plan =. id get_key plans
            item =. id get_key Items
            released =. week{'planned_releases' get_key plan
            inventory =. inventory+(week{'on_hand' get_key plan)*'total' get_key id get_key Costs
            if. #id get_key Children do. labor =. labor+released*'labor' get_key item
            else. purchases =. purchases+released*'material' get_key item end.
        end.
        lines =. lines,<(number week+1),',',(money inventory),',',(money purchases),',',money labor
    end.
    lines
)
main =: 3 : 0
    read_data ''
    base =. run_mrp 0$a:
    'promises final' =. promise_inquiries base
    final =. peg_plan final
    standard_costs ''
    1!:5 <'output'
    'mrp_grid.txt' write_report grid_lines final
    'pegging.txt' write_report pegging_lines final
    'bom_tree.txt' write_report bom_tree_lines ''
    'cost_rollup.csv' write_report cost_lines final
    'exceptions.txt' write_report exception_lines final
    'capacity.txt' write_report capacity_lines final
    'promises.txt' write_report promise_lines (<promises),(<base),<final
    'releases.txt' write_report release_lines final
    'value_plan.csv' write_report value_plan_lines final
    i.0
)
main ''
