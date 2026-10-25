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
empty_table =: 3 : '0 2$a:'
table_keys =: 3 : '0{"1 y'
table_values =: 3 : '1{"1 y'
has_key =: 4 : '(<x)e.table_keys y'
get_key =: 4 : '((table_keys y)i.<x){::table_values y'
put_key =: 4 : 0
    'key value' =. x
    position =. (table_keys y)i.<key
    if. position<#y do. (<value) (<position,1)}y
    else. y,1 2$(<key),<value end.
)
increment_key =: 4 : 0
    'key delta' =. x
    value =. delta
    if. key has_key y do. value =. value+key get_key y end.
    ((<key),<value) put_key y
)
record =: 4 : '('' '' split x),.y'
load SourceDirectory,'rules.ijs'
load SourceDirectory,'report.ijs'
load SourceDirectory,'baskets.ijs'
load SourceDirectory,'apriori.ijs'
load SourceDirectory,'fpgrowth.ijs'
Segments =: ' ' split 'NEW LOYAL AT_RISK REGULAR'
read_params =: 3 : 0
    Params =: empty_table ''
    for_box. read_lines 'params.txt' do.
        'key text' =. ' ' split >box
        pieces =. num&>'/' split text
        if. 1=#pieces do. value =. {.pieces else. value =. ({.pieces) fraction {:pieces end.
        Params =: ((<key),<value) put_key Params
    end.
    i.0
)
record_error =: 3 : 0
    'file line message' =. y
    Errors =: Errors,<file,' line ',(number line),': ',message
    i.0
)
read_dataset =: 3 : 0
    Errors =: 0$a:
    Products =: empty_table ''
    rows =. read_records 'items.csv'
    ItemRows =: #rows
    for_index. i.#rows do.
        'name category text' =. index{::rows
        price =. num text
        problem =. ''
        if. name has_key Products do. problem =. 'duplicate item ',name
        elseif. price=0 do. problem =. 'bad price 0' end.
        if. #problem do. record_error (<'items.csv'),(<index+2),<problem
        else. Products =: ((<name),<product_record (<name),(<category),<price) put_key Products end.
    end.
    Transactions =: 0$a:
    known =. 0$a:
    Adopted =: Rejected =: Duplicates =: 0
    rows =. read_records 'transactions.csv'
    TransactionLines =: #rows
    for_index. i.#rows do.
        'tid customer text item' =. index{::rows
        day =. num text
        problem =. ''
        noncontiguous =. 0
        if. (<tid)e.known do. noncontiguous =. -.tid-:'tid' get_key >{:Transactions end.
        if. noncontiguous do. problem =. 'tid ',tid,' not contiguous'
        else.
            if. -. (<tid)e.known do.
                known =. known,<tid
                Transactions =: Transactions,<transaction_record (<tid),(<customer),<day
            end.
            current =. >{:Transactions
            if. -.customer-:'customer' get_key current do. problem =. 'tid ',tid,' customer ',customer,' differs from ','customer' get_key current
            elseif. day~:'day' get_key current do. problem =. 'tid ',tid,' day ',(number day),' differs from ',number 'day' get_key current
            elseif. -.item has_key Products do. problem =. 'unknown item ',item end.
        end.
        if. #problem do.
            record_error (<'transactions.csv'),(<index+2),<problem
            Rejected =: Rejected+1
        else.
            Adopted =: Adopted+1
            Duplicates =: Duplicates+item has_key 'counts' get_key current
            current =. item add_product current
            Transactions =: (<current) (<:#Transactions)}Transactions
        end.
    end.
    ProductNames =: /:~table_keys Products
    Taxonomy =: empty_table ''
    for_itembox. ProductNames do. Taxonomy =: (itembox,<'category' get_key (>itembox) get_key Products) put_key Taxonomy end.
    Categories =: /:~~.table_values Taxonomy
    Baskets =: ItemSets =: 0$a:
    CustomerBaskets =: empty_table ''
    days =. 0$0
    for_box. Transactions do.
        basket =. >box
        items =. basket_items basket
        if. 0=#items do. continue. end.
        Baskets =: Baskets,box
        ItemSets =: ItemSets,<items
        customer =. 'customer' get_key basket
        chosen =. 0$a:
        if. customer has_key CustomerBaskets do. chosen =. customer get_key CustomerBaskets end.
        CustomerBaskets =: ((<customer),<chosen,box) put_key CustomerBaskets
        days =. days,'day' get_key basket
    end.
    Total =: #Baskets
    Customers =: /:~table_keys CustomerBaskets
    FirstDay =: <./days
    LastDay =: >./days
    i.0
)
size_keys =: 3 : 0
    keys =. 0 2$a:
    for_keybox. y do. keys =. keys,1 2$(<#split_itemset_text >keybox),keybox end.
    (/:keys){y
)
support_in =: 3 : 0
    'supports total items' =. y
    if. #items do. (itemset_text items) get_key supports else. total end.
)
split_mask =: 4 : 0
    bits =. |.((#y)#2)#:x
    (<bits#y),<(-.bits)#y
)
exact_median =: 3 : 0
    ordered =. /:~y
    middle =. (#y) div 2
    if. 2|#y do. x:middle{ordered
    else. ((middle{ordered)+(middle-1){ordered) fraction 2 end.
)
run_apriori =: 3 : 0
    'baskets universe minimum taxonomy' =. y
    previous =. <"1 ,. /:~universe
    levels =. 0$a:
    supports =. singles =. empty_table ''
    size =. 1
    while. 1 do.
        if. size=1 do. generation =. 'joined excluded pruned itemsets' record (<#previous),(<0),(<0),<previous
        else. generation =. generate_candidates (<previous),(<size),<taxonomy end.
        candidates =. 'itemsets' get_key generation
        counts =. baskets count_supports candidates
        if. size=1 do. singles =. counts end.
        previous =. 0$a:
        for_candidatebox. candidates do.
            candidate =. >candidatebox
            key =. itemset_text candidate
            count =. key get_key counts
            if. count>:minimum do.
                previous =. previous,candidatebox
                supports =. ((<key),<count) put_key supports
            end.
        end.
        level =. 'number candidates excluded pruned counted itemsets' record (<size),(<'joined' get_key generation),(<'excluded' get_key generation),(<'pruned' get_key generation),(<#candidates),<previous
        levels =. levels,<level
        size =. size+1
        if. (size>'max_size' get_key Params)+.0=#previous do. break. end.
    end.
    'levels supports singles' record (<levels),(<supports),<singles
)
make_rules =: 3 : 0
    'supports total required' =. y
    generated =. 0
    kept =. 0$a:
    for_row. supports do.
        'key count' =. row
        itemset =. split_itemset_text key
        if. (#itemset)<2 do. continue. end.
        if. #required do. if. -. +./itemset e.required do. continue. end. end.
        lastmask =. 2#.(#itemset)#1
        for_mask. >:i.lastmask-1 do.
            'first second' =. mask split_mask itemset
            generated =. generated+1
            firstcount =. support_in (<supports),(<total),<first
            secondcount =. support_in (<supports),(<total),<second
            rule =. rule_record (<itemset),(<first),(<second),(<count),(<total),(<firstcount),<secondcount
            if. -. meets_thresholds ('confidence' get_key rule),'lift' get_key rule do. continue. end.
            reference =. 0x
            subsetlimit =. 2#.(#first)#1
            for_subsetmask. i.subsetlimit do.
                subset =. 0{::subsetmask split_mask first
                joined =. /:~subset,second
                together =. support_in (<supports),(<total),<joined
                base =. support_in (<supports),(<total),<subset
                reference =. reference>.together fraction base
            end.
            improvement =. ('confidence' get_key rule)-reference
            rule =. ((<'improvement'),<improvement) put_key rule
            kept =. kept,<rule
        end.
    end.
    kept =. sort_rules kept
    productive =. 0
    for_box. kept do. productive =. productive+0<'improvement' get_key >box end.
    'generated rules productive' record (<generated),(<kept),<productive
)
recommend =: 3 : 0
    'held candidates' =. y
    selected =. 0$a:
    for_itembox. candidates do.
        if. (#selected)='recommend_top' get_key Params do. break. end.
        if. -.itembox e.held,selected do. selected =. selected,itembox end.
    end.
    selected
)
rule_candidates =: 4 : 0
    candidates =. 0$a:
    for_box. x do.
        rule =. >box
        consequent =. 'consequent' get_key rule
        if. (1=#consequent)*.y contains 'antecedent' get_key rule do. candidates =. candidates,consequent end.
    end.
    candidates
)
analyze_frequent =: 3 : 0
    MainRun =: run_apriori (<ItemSets),(<ProductNames),(<'min_support' get_key Params),<empty_table ''
    Frequent =: 'supports' get_key MainRun
    Counts =: 'singles' get_key MainRun
    base =. 0$a:
    for_box. ItemSets do. base =. base,<box,<1 end.
    Growth =: fp_growth (<base),(<'min_support' get_key Params),<'max_size' get_key Params
    Closed =: Maximal =: table_keys Frequent
    Generators =: 0$a:
    Pairs =: 0$a:
    for_row. Frequent do.
        'key count' =. row
        items =. split_itemset_text key
        if. 2=#items do. Pairs =: Pairs,<items end.
        generator =. 1
        for_subsetbox. one_smaller_subsets items do.
            subset =. >subsetbox
            smaller =. support_in (<Frequent),(<Total),<subset
            if. smaller<:count do. generator =. 0 end.
            if. #subset do.
                smallerkey =. <itemset_text subset
                Maximal =: Maximal-.smallerkey
                if. smaller=count do. Closed =: Closed-.smallerkey end.
            end.
        end.
        if. generator do. Generators =: Generators,<key end.
    end.
    Closed =: size_keys Closed
    Maximal =: size_keys Maximal
    Generators =: size_keys Generators
    MainRules =: make_rules (<Frequent),(<Total),<0$a:
    ExtendedSets =: 0$a:
    for_box. ItemSets do. ExtendedSets =: ExtendedSets,<Taxonomy extended_basket >box end.
    CategoryRun =: run_apriori (<ExtendedSets),(<ProductNames,Categories),(<'category_min_support' get_key Params),<Taxonomy
    CategoryRules =: make_rules (<'supports' get_key CategoryRun),(<Total),<Categories
    i.0
)
analyze_sequences =: 3 : 0
    Histories =: Buyers =: empty_table ''
    for_itembox. ProductNames do. Buyers =: (itembox,<0) put_key Buyers end.
    gaps =. intervals =. repeaters =. empty_table ''
    for_customerbox. Customers do.
        customer =. >customerbox
        history =. empty_table ''
        for_basketbox. customer get_key CustomerBaskets do.
            basket =. >basketbox
            day =. 'day' get_key basket
            for_itembox. basket_items basket do.
                item =. >itembox
                days =. 0$0
                if. item has_key history do. days =. item get_key history end.
                history =. (itembox,</:~~.days,day) put_key history
            end.
        end.
        Histories =: (customerbox,<history) put_key Histories
        names =. /:~table_keys history
        for_firstbox. names do.
            first =. >firstbox
            Buyers =: (firstbox,<1) increment_key Buyers
            firstdays =. first get_key history
            if. 1<#firstdays do.
                found =. 0$0
                if. first has_key intervals do. found =. first get_key intervals end.
                intervals =. (firstbox,<found,(}.firstdays)-}:firstdays) put_key intervals
                repeaters =. (firstbox,<1) increment_key repeaters
            end.
            for_secondbox. names do.
                second =. >secondbox
                seconddays =. second get_key history
                if. ({.firstdays)<{:seconddays do.
                    shortest =. 113
                    for_earlier. firstdays do.
                        for_later. seconddays do.
                            if. earlier<later do. shortest =. shortest<.later-earlier end.
                        end.
                    end.
                    key =. first,'/',second
                    found =. 0$0
                    if. key has_key gaps do. found =. key get_key gaps end.
                    gaps =. ((<key),<found,shortest) put_key gaps
                end.
            end.
        end.
    end.
    SequencePairs =: #gaps
    sequences =. 0$a:
    keys =. 0 4$a:
    for_row. gaps do.
        'key found' =. row
        count =. #found
        if. count<'sequence_min_support' get_key Params do. continue. end.
        'first second' =. '/' split key
        base =. first get_key Buyers
        confidence =. count fraction base
        lift =. lift_of (#Customers),count,base,second get_key Buyers
        sequence =. 'first second count base confidence lift gap' record (<first),(<second),(<count),(<base),(<confidence),(<lift),<exact_median found
        sequences =. sequences,<sequence
        keys =. keys,1 4$(<-count),(<-confidence),(<first),<second
    end.
    Sequences =: (/:keys){sequences
    repeats =. 0$a:
    keys =. 0 2$a:
    for_row. intervals do.
        'item found' =. row
        mean =. (+/found) fraction #found
        repeat =. 'name customers count minimum maximum mean median' record (<item),(<item get_key repeaters),(<#found),(<<./found),(<>./found),(<mean),<exact_median found
        repeats =. repeats,<repeat
        keys =. keys,1 2$(<mean),<item
    end.
    Repeats =: (/:keys){repeats
    i.0
)
new_tally =: 3 : '5$0'
add_tally =: 4 : 0
    'heldout suggestion baseline' =. y
    covered =. 0<#suggestion
    top =. 0
    if. covered do. top =. (<heldout)-:{.suggestion end.
    x+1,covered,top,((<heldout)e.suggestion),(<heldout)e.baseline
)
tally_text =: 3 : 0
    'cases covered top hit baseline' =. y
    text_line (<'cases'),(<cases),(<'covered'),(<covered),(<'hit1'),(<top),(<'hit'),(<hit),(<'rate'),(<fraction_text hit fraction cases),(<'baseline'),(<baseline),(<'rate'),<fraction_text baseline fraction cases
)
analyze_validation =: 3 : 0
    train =. test =. 0$a:
    for_basketbox. Baskets do.
        basket =. >basketbox
        items =. basket_items basket
        if. ('day' get_key basket)<:'split_day' get_key Params do. train =. train,<items else. test =. test,<items end.
    end.
    TrainTotal =: #train
    TestTotal =: #test
    TrainRun =: run_apriori (<train),(<ProductNames),(<'train_min_support' get_key Params),<empty_table ''
    TrainRules =: 'rules' get_key make_rules (<'supports' get_key TrainRun),(<TrainTotal),<0$a:
    needed =. 0$a:
    for_box. TrainRules do.
        rule =. >box
        needed =. needed,(<'antecedent' get_key rule),(<'consequent' get_key rule),<'itemset' get_key rule
    end.
    counts =. test count_supports needed
    Checks =: 0$a:
    for_box. TrainRules do.
        rule =. >box
        first =. (itemset_text 'antecedent' get_key rule) get_key counts
        second =. (itemset_text 'consequent' get_key rule) get_key counts
        together =. (itemset_text 'itemset' get_key rule) get_key counts
        confidence =. lift =. '-'
        verdict =. 'UNSEEN'
        if. (first>0)*.second>0 do.
            confidence =. together fraction first
            lift =. lift_of TestTotal,together,first,second
            verdict =. (meets_thresholds confidence,lift){::'FAIL';'HOLD'
        end.
        Checks =: Checks,<'rule first count confidence lift verdict' record (<rule),(<first),(<together),(<confidence),(<lift),<verdict
    end.
    testrun =. run_apriori (<test),(<ProductNames),(<'test_min_support' get_key Params),<empty_table ''
    testrules =. 'rules' get_key make_rules (<'supports' get_key testrun),(<TestTotal),<0$a:
    known =. 0$a:
    for_box. TrainRules do. known =. known,<rule_arrow >box end.
    Emerging =: 0$a:
    for_box. testrules do. if. -. (<rule_arrow >box)e.known do. Emerging =: Emerging,box end. end.
    popularitykeys =. 0 2$a:
    traincounts =. 'singles' get_key TrainRun
    for_itembox. ProductNames do. popularitykeys =. popularitykeys,1 2$(<-(>itembox) get_key traincounts),itembox end.
    popularity =. (/:popularitykeys){ProductNames
    Tallies =: empty_table ''
    Overall =: new_tally ''
    HeldOut =: HeldHits =: empty_table ''
    for_itembox. ProductNames do.
        HeldOut =: (itembox,<0) put_key HeldOut
        HeldHits =: (itembox,<0) put_key HeldHits
    end.
    for_itemsbox. test do.
        items =. >itemsbox
        size =. #items
        if. size<2 do. continue. end.
        key =. number size
        tally =. new_tally ''
        if. key has_key Tallies do. tally =. key get_key Tallies end.
        for_heldoutbox. items do.
            heldout =. >heldoutbox
            held =. items-.heldoutbox
            suggestion =. recommend (<held),<TrainRules rule_candidates held
            baseline =. recommend (<held),<popularity
            tally =. tally add_tally (<heldout),(<suggestion),<baseline
            Overall =: Overall add_tally (<heldout),(<suggestion),<baseline
            HeldOut =: (heldoutbox,<1) increment_key HeldOut
            if. heldoutbox e.suggestion do. HeldHits =: (heldoutbox,<1) increment_key HeldHits end.
        end.
        Tallies =: ((<key),<tally) put_key Tallies
    end.
    i.0
)
pair_lift =: 3 : 'lift_of Total,((itemset_text y) get_key Frequent),((0{::y) get_key Counts),(1{::y) get_key Counts'
analyze_products =: 3 : 0
    Units =: Revenue =: empty_table ''
    for_itembox. ProductNames do. Units =: (itembox,<0) put_key Units end.
    for_box. Baskets do.
        for_row. 'counts' get_key >box do. Units =: row increment_key Units end.
    end.
    TotalRevenue =: 0
    for_itembox. ProductNames do.
        item =. >itembox
        revenue =. (item get_key Units)*'price' get_key item get_key Products
        Revenue =: (itembox,<revenue) put_key Revenue
        TotalRevenue =: TotalRevenue+revenue
    end.
    categories =. 0$a:
    keys =. 0 2$a:
    for_categorybox. Categories do.
        category =. >categorybox
        units =. revenue =. count =. 0
        for_itembox. ProductNames do.
            item =. >itembox
            if. category-:item get_key Taxonomy do.
                count =. count+1
                units =. units+item get_key Units
                revenue =. revenue+item get_key Revenue
            end.
        end.
        baskets =. category get_key 'singles' get_key CategoryRun
        categories =. categories,<'name products units revenue baskets' record (<category),(<count),(<units),(<revenue),<baskets
        keys =. keys,1 2$(<-revenue),<category
    end.
    CategorySummaries =: (/:keys){categories
    neighbors =. empty_table ''
    for_itembox. ProductNames do. neighbors =. (itembox,<0$a:) put_key neighbors end.
    edges =. 0$a:
    for_pairbox. Pairs do.
        pair =. >pairbox
        if. (pair_lift pair)>:'group_min_lift' get_key Params do.
            edges =. edges,pairbox
            'first second' =. pair
            neighbors =. ((<first),<(first get_key neighbors),<second) put_key neighbors
            neighbors =. ((<second),<(second get_key neighbors),<first) put_key neighbors
        end.
    end.
    visited =. 0$a:
    groups =. 0$a:
    keys =. 0 2$a:
    for_itembox. ProductNames do.
        item =. >itembox
        if. (itembox e.visited)+.0=#item get_key neighbors do. continue. end.
        members =. 0$a:
        stack =. itembox
        visited =. visited,itembox
        while. #stack do.
            current =. >{:stack
            stack =. }:stack
            members =. members,<current
            added =. (current get_key neighbors)-.visited
            visited =. visited,added
            stack =. stack,added
        end.
        members =. /:~members
        corekeys =. 0 3$a:
        revenue =. 0
        for_memberbox. members do.
            member =. >memberbox
            revenue =. revenue+member get_key Revenue
            corekeys =. corekeys,1 3$(<-#member get_key neighbors),(<-member get_key Counts),memberbox
        end.
        core =. ({./:corekeys){::members
        edgecount =. 0
        for_edgebox. edges do. edgecount =. edgecount+({.>edgebox)e.members end.
        groups =. groups,<'members edges core revenue' record (<members),(<edgecount),(<core),<revenue
        keys =. keys,1 2$(<-#members),{.members
    end.
    Groups =: (/:keys){groups
    singles =. 'itemsets' get_key 0{::'levels' get_key MainRun
    names =. 0$a:
    for_singlebox. singles do. names =. names,{.>singlebox end.
    candidates =. 0$a:
    for_firstindex. i.#names do.
        first =. firstindex{::names
        for_secondbox. (firstindex+1)}.names do.
            second =. >secondbox
            if. ((first get_key Counts)*second get_key Counts)>:('negative_min_expected' get_key Params)*Total do. candidates =. candidates,<( <first),<second end.
        end.
    end.
    together =. ItemSets count_supports candidates
    substitutes =. 0$a:
    keys =. 0 4$a:
    for_pairbox. candidates do.
        pair =. >pairbox
        'first second' =. pair
        count =. (itemset_text pair) get_key together
        expected =. ((first get_key Counts)*second get_key Counts) fraction Total
        lift =. lift_of Total,count,(first get_key Counts),second get_key Counts
        if. lift<:'negative_max_lift' get_key Params do.
            substitutes =. substitutes,<'first second count expected lift' record (<first),(<second),(<count),(<expected),<lift
            keys =. keys,1 4$(<lift),(<-expected),(<first),<second
        end.
    end.
    Substitutes =: (/:keys){substitutes
    i.0
)
week_of =: 3 : '1+(y-1) div 7'
analyze_trends =: 3 : 0
    WeekCount =: week_of LastDay
    WeekBaskets =: WeekUnits =: WeekCount$0
    weekcustomers =. WeekCount#<0$a:
    Series =: empty_table ''
    for_namebox. Categories,ProductNames do. Series =: (namebox,<WeekCount$0) put_key Series end.
    for_box. Baskets do.
        basket =. >box
        week =. <:week_of 'day' get_key basket
        counts =. 'counts' get_key basket
        WeekBaskets =: (1+week{WeekBaskets) week}WeekBaskets
        WeekUnits =: ((week{WeekUnits)+ +/>table_values counts) week}WeekUnits
        customers =. ~.(week{::weekcustomers),<'customer' get_key basket
        weekcustomers =. (<customers) week}weekcustomers
        for_row. counts do.
            'product count' =. row
            for_namebox. (<product),<product get_key Taxonomy do.
                name =. >namebox
                values =. name get_key Series
                values =. (count+week{values) week}values
                Series =: (namebox,<values) put_key Series
            end.
        end.
    end.
    WeekCustomers =: #&>weekcustomers
    weeks =. >:i.WeekCount
    weeksum =. +/weeks
    denominator =. (WeekCount*+/weeks*weeks)-weeksum*weeksum
    rated =. unrated =. 0$a:
    keys =. 0 2$a:
    for_row. Series do.
        'name values' =. row
        units =. +/values
        slope =. ((WeekCount*+/weeks*values)-weeksum*units) fraction denominator
        relative =. '-'
        verdict =. 'NONE'
        if. units>0 do.
            relative =. slope*(WeekCount fraction units)
            threshold =. 'trend_threshold' get_key Params
            if. relative>:threshold do. verdict =. 'RISING'
            elseif. relative<:-threshold do. verdict =. 'FALLING'
            else. verdict =. 'FLAT' end.
        end.
        trend =. 'name units slope relative verdict' record (<name),(<units),(<slope),(<relative),<verdict
        if. units>0 do.
            rated =. rated,<trend
            keys =. keys,1 2$(<-relative),<name
        else. unrated =. unrated,<trend end.
    end.
    names =. 0$a:
    for_box. unrated do. names =. names,<'name' get_key >box end.
    Trends =: ((/:keys){rated),(/:names){unrated
    i.0
)
analyze_customers =: 3 : 0
    CustomerSummaries =: 0$a:
    for_customerbox. Customers do.
        customer =. >customerbox
        baskets =. customer get_key CustomerBaskets
        days =. 0$0
        units =. revenue =. 0
        categoryunits =. (#Categories)$0
        for_basketbox. baskets do.
            basket =. >basketbox
            days =. days,'day' get_key basket
            for_row. 'counts' get_key basket do.
                'name count' =. row
                units =. units+count
                product =. name get_key Products
                revenue =. revenue+count*'price' get_key product
                index =. Categories i.<'category' get_key product
                categoryunits =. (count+index{categoryunits) index}categoryunits
            end.
        end.
        days =. /:~~.days
        first =. {.days
        last =. {:days
        favorite =. (categoryunits i.>./categoryunits){::Categories
        if. first>LastDay-28 do. segment =. 'NEW'
        elseif. ((#baskets)>:4)*.(LastDay-last)<:14 do. segment =. 'LOYAL'
        elseif. (LastDay-last)>28 do. segment =. 'AT_RISK'
        else. segment =. 'REGULAR' end.
        held =. table_keys customer get_key Histories
        offer =. recommend (<held),<('rules' get_key MainRules) rule_candidates held
        summary =. 'customer baskets days first last products units revenue average favorite segment offer' record (<customer),(<#baskets),(<#days),(<first),(<last),(<#held),(<units),(<revenue),(<revenue div #baskets),(<favorite),(<segment),<offer
        CustomerSummaries =: CustomerSummaries,<summary
    end.
    i.0
)
growth_lines =: 3 : 0
    expected =. Frequent
    found =. 'supports' get_key Growth
    onlymain =. onlygrowth =. 0$a:
    for_row. expected do.
        'key count' =. row
        match =. 0
        if. key has_key found do. match =. count=key get_key found end.
        if. -.match do. onlymain =. onlymain,<key end.
    end.
    for_row. found do.
        'key count' =. row
        match =. 0
        if. key has_key expected do. match =. count=key get_key expected end.
        if. -.match do. onlygrowth =. onlygrowth,<key end.
    end.
    if. (#onlymain)+#onlygrowth do. status =. 'MISMATCH' else. status =. 'MATCH' end.
    add_line (<'FPGROWTH header'),(<'header' get_key Growth),(<'nodes'),(<'nodes' get_key Growth),(<'conditional_trees'),(<'conditional_trees' get_key Growth),(<'conditional_nodes'),(<'conditional_nodes' get_key Growth),(<'itemsets'),(<#found),<status
    for_keybox. size_keys onlymain do. add_line (<'ONLY_APRIORI'),keybox,< (>keybox) get_key expected end.
    for_keybox. size_keys onlygrowth do. add_line (<'ONLY_FPGROWTH'),keybox,< (>keybox) get_key found end.
    i.0
)
summary_lines =: 3 : 0
    ReportLines =: 0$a:
    for_errorbox. Errors do. add_line (<'ERROR'),errorbox end.
    add_line (<'ITEMS rows'),(<ItemRows),(<'adopted'),(<#Products),(<'categories'),<#Categories
    add_line (<'TRANSACTIONS lines'),(<TransactionLines),(<'adopted'),(<Adopted),(<'rejected'),(<Rejected),(<'duplicates'),(<Duplicates),(<'transactions'),(<#Transactions),(<'empty'),<(#Transactions)-Total
    sizes =. #&>ItemSets
    largest =. >./sizes
    add_line (<'BASKETS count'),(<Total),(<'customers'),(<#Customers),(<'first_day'),(<FirstDay),(<'last_day'),(<LastDay),(<'average_size'),(<fraction_text (+/sizes) fraction Total),(<'largest'),<largest
    for_size. >:i.largest do.
        count =. +/sizes=size
        add_line (<'SIZE'),(<size),(<'baskets'),(<count),(<'share'),<count percent_text Total
    end.
    add_line (<'FREQUENT itemsets'),(<#Frequent),(<'closed'),(<#Closed),(<'maximal'),(<#Maximal),(<'generators'),(<#Generators),(<'levels'),<#'levels' get_key MainRun
    growth_lines ''
    add_line (<'RULES generated'),(<'generated' get_key MainRules),(<'passed'),(<#'rules' get_key MainRules),(<'productive'),<'productive' get_key MainRules
    for_box. 'levels' get_key CategoryRun do.
        level =. >box
        add_line (<'CATEGORY_LEVEL'),(<'number' get_key level),(<'candidates'),(<'candidates' get_key level),(<'taxonomy'),(<'excluded' get_key level),(<'pruned'),(<'pruned' get_key level),(<'counted'),(<'counted' get_key level),(<'frequent'),<#'itemsets' get_key level
    end.
    add_line (<'CATEGORY_RULES itemsets'),(<#'supports' get_key CategoryRun),(<'generated'),(<'generated' get_key CategoryRules),(<'passed'),(<#'rules' get_key CategoryRules),(<'productive'),<'productive' get_key CategoryRules
    multiday =. 0
    for_box. CustomerSummaries do. multiday =. multiday+('days' get_key >box)>:2 end.
    add_line (<'SEQUENCES customers'),(<#Customers),(<'multi_day'),(<multiday),(<'pairs'),(<SequencePairs),(<'frequent'),<#Sequences
    ReportLines
)
itemset_lines =: 3 : 0
    ReportLines =: 0$a:
    for_box. 'levels' get_key MainRun do.
        level =. >box
        itemsets =. 'itemsets' get_key level
        add_line (<'LEVEL'),(<'number' get_key level),(<'candidates'),(<'candidates' get_key level),(<'pruned'),(<'pruned' get_key level),(<'counted'),(<'counted' get_key level),(<'frequent'),<#itemsets
        for_itemsetbox. itemsets do.
            key =. itemset_text >itemsetbox
            add_line (<key),<key get_key Frequent
        end.
    end.
    ReportLines
)
closed_lines =: 3 : 0
    ReportLines =: 0$a:
    names =. 'CLOSED';'MAXIMAL';'GENERATOR'
    sets =. (<Closed),(<Maximal),<Generators
    for_index. i.3 do.
        for_keybox. index{::sets do. add_line (index{names),keybox,< (>keybox) get_key Frequent end.
    end.
    ReportLines
)
sequence_lines =: 3 : 0
    ReportLines =: 0$a:
    for_index. i.#Sequences do.
        sequence =. index{::Sequences
        add_line (<'SEQ'),(<index+1),(<'first' get_key sequence),(<'->'),(<'second' get_key sequence),(<'customers'),(<'count' get_key sequence),(<'base'),(<'base' get_key sequence),(<'confidence'),(<fraction_text 'confidence' get_key sequence),(<'lift'),(<fraction_text 'lift' get_key sequence),(<'gap'),<fraction_text 'gap' get_key sequence
    end.
    for_box. Repeats do.
        repeat =. >box
        add_line (<'REPEAT'),(<'name' get_key repeat),(<'customers'),(<'customers' get_key repeat),(<'intervals'),(<'count' get_key repeat),(<'min'),(<'minimum' get_key repeat),(<'max'),(<'maximum' get_key repeat),(<'mean'),(<fraction_text 'mean' get_key repeat),(<'median'),<fraction_text 'median' get_key repeat
    end.
    ReportLines
)
validation_lines =: 3 : 0
    ReportLines =: 0$a:
    verdictcounts =. 3$0
    verdictnames =. 'HOLD';'FAIL';'UNSEEN'
    for_box. Checks do.
        check =. >box
        rule =. 'rule' get_key check
        verdict =. 'verdict' get_key check
        index =. verdictnames i.<verdict
        verdictcounts =. (1+index{verdictcounts) index}verdictcounts
        if. verdict-:'UNSEEN' do. measured =. 'confidence - lift -'
        else. measured =. 'confidence ',(fraction_text 'confidence' get_key check),' lift ',fraction_text 'lift' get_key check end.
        add_line (<'RULE'),(<'rank' get_key rule),(<rule_arrow rule),(<'train'),(<'count' get_key rule),(<'confidence'),(<fraction_text 'confidence' get_key rule),(<'lift'),(<fraction_text 'lift' get_key rule),(<'test'),(<'count' get_key check),(<'of'),(<'first' get_key check),(<measured),<verdict
    end.
    for_box. Emerging do.
        rule =. >box
        add_line (<'EMERGING'),(<'rank' get_key rule),(<rule_arrow rule),(<'test'),(<'count' get_key rule),(<'confidence'),(<fraction_text 'confidence' get_key rule),(<'lift'),<fraction_text 'lift' get_key rule
    end.
    add_line (<'VALIDATION train'),(<TrainTotal),(<'test'),(<TestTotal),(<'itemsets'),(<#'supports' get_key TrainRun),(<'rules'),(<#TrainRules),(<'hold'),(<0{verdictcounts),(<'fail'),(<1{verdictcounts),(<'unseen'),(<2{verdictcounts),(<'emerging'),<#Emerging
    sizes =. /:~num&>table_keys Tallies
    for_size. sizes do. add_line (<'RECOMMEND size'),(<size),<tally_text (number size) get_key Tallies end.
    add_line (<'RECOMMEND total'),<tally_text Overall
    ReportLines
)
partner_text =: 3 : 0
    partners =. 0$a:
    keys =. 0 3$a:
    for_pairbox. Pairs do.
        pair =. >pairbox
        if. (<y)e.pair do.
            other =. >{.pair-.<y
            lift =. pair_lift pair
            partners =. partners,<other,' ',fraction_text lift
            keys =. keys,1 3$(<-lift),(<-(itemset_text pair) get_key Frequent),<other
        end.
    end.
    if. #partners do. ({./:keys){::partners else. 'none' end.
)
strongest_text =: 3 : 0
    for_box. 'rules' get_key MainRules do.
        rule =. >box
        if. (<y)e.'itemset' get_key rule do. (number 'rank' get_key rule),' ',rule_arrow rule return. end.
    end.
    'none'
)
right_pad =: 4 : 0
    ((0>.x-#y)#' '),y
)
matrix_lines =: 3 : 0
    'label items counts baskets' =. y
    pairs =. 0$a:
    for_firstindex. i.#items do.
        for_secondbox. (firstindex+1)}.items do. pairs =. pairs,</:~(firstindex{items),secondbox end.
    end.
    together =. baskets count_supports pairs
    for_index. i.#items do.
        item =. index{::items
        add_line (<label),(<index+1),(<item),(<'baskets'),<item get_key counts
    end.
    heading =. 4#' '
    for_index. >:i.#items do. heading =. heading,7 right_pad number index end.
    ReportLines =: ReportLines,<heading
    for_firstindex. i.#items do.
        first =. firstindex{::items
        line =. 4 right_pad number firstindex+1
        for_secondindex. i.#items do.
            if. firstindex=secondindex do. value =. '-'
            else.
                second =. secondindex{::items
                key =. itemset_text /:~(<first),<second
                numerator =. (100*#baskets)*key get_key together
                denominator =. (first get_key counts)*second get_key counts
                value =. number numerator div denominator
            end.
            line =. line,7 right_pad value
        end.
        ReportLines =: ReportLines,<line
    end.
    i.0
)
item_lines =: 3 : 0
    ReportLines =: 0$a:
    keys =. 0 2$a:
    for_itembox. ProductNames do. keys =. keys,1 2$(<-(>itembox) get_key Revenue),itembox end.
    ranked =. (/:keys){ProductNames
    for_index. i.#ranked do.
        item =. index{::ranked
        product =. item get_key Products
        count =. item get_key Counts
        containing =. 0
        for_keybox. table_keys Frequent do. containing =. containing+(<item)e.split_itemset_text >keybox end.
        add_line (<'ITEM'),(<index+1),(<item),(<'category' get_key product),(<'price'),(<money_text 'price' get_key product),(<'units'),(<item get_key Units),(<'revenue'),(<money_text item get_key Revenue),(<'share'),(<(item get_key Revenue) percent_text TotalRevenue),(<'baskets'),(<count),(<'support'),(<fraction_text count fraction Total),(<'customers'),(<item get_key Buyers),(<'itemsets'),(<containing),(<'heldout'),(<item get_key HeldOut),(<'hits'),(<item get_key HeldHits),(<'partner'),(<partner_text item),(<'best'),<strongest_text item
    end.
    for_box. CategorySummaries do.
        category =. >box
        add_line (<'CATEGORY'),(<'name' get_key category),(<'items'),(<'products' get_key category),(<'units'),(<'units' get_key category),(<'revenue'),(<money_text 'revenue' get_key category),(<'share'),(<('revenue' get_key category) percent_text TotalRevenue),(<'baskets'),(<'baskets' get_key category),(<'support'),<fraction_text ('baskets' get_key category) fraction Total
    end.
    add_line (<'TOTAL items'),(<#Products),(<'units'),(<+/>table_values Units),(<'revenue'),(<money_text TotalRevenue),(<'baskets'),(<Total),(<'customers'),<#Customers
    for_index. i.#Groups do.
        group =. index{::Groups
        add_line (<'GROUP'),(<index+1),(<'items'),(<#'members' get_key group),(<'edges'),(<'edges' get_key group),(<'core'),(<'core' get_key group),(<'revenue'),(<money_text 'revenue' get_key group),(<'share'),(<('revenue' get_key group) percent_text TotalRevenue),(<'members'),<itemset_text 'members' get_key group
    end.
    for_box. Substitutes do.
        substitute =. >box
        add_line (<'SUBSTITUTE'),(<'first' get_key substitute),(<'second' get_key substitute),(<'count'),(<'count' get_key substitute),(<'expected'),(<fraction_text 'expected' get_key substitute),(<'lift'),<fraction_text 'lift' get_key substitute
    end.
    keys =. 0 2$a:
    for_itembox. ProductNames do. keys =. keys,1 2$(<-(>itembox) get_key Counts),itembox end.
    ordered =. (/:keys){ProductNames
    top =. ('matrix_size' get_key Params){.ordered
    matrix_lines (<'MATRIX'),(<top),(<Counts),<ItemSets
    counts =. 'singles' get_key CategoryRun
    keys =. 0 2$a:
    for_categorybox. Categories do. keys =. keys,1 2$(<-(>categorybox) get_key counts),categorybox end.
    top =. (/:keys){Categories
    matrix_lines (<'CATEGORY_MATRIX'),(<top),(<counts),<ExtendedSets
    ReportLines
)
table_row =: 4 : 0
    line =. x,(17-#x)#' '
    for_value. y do. line =. line,6 right_pad number value end.
    line
)
trend_lines =: 3 : 0
    ReportLines =: (<'WEEK' table_row >:i.WeekCount),(<'BASKETS' table_row WeekBaskets),(<'UNITS' table_row WeekUnits),<'CUSTOMERS' table_row WeekCustomers
    for_namebox. Categories,ProductNames do.
        name =. >namebox
        ReportLines =: ReportLines,<name table_row name get_key Series
    end.
    for_box. Trends do.
        trend =. >box
        relative =. 'relative' get_key trend
        if. 2~:3!:0 relative do. relative =. fraction_text relative end.
        add_line (<'TREND'),(<'name' get_key trend),(<'units'),(<'units' get_key trend),(<'slope'),(<fraction_text 'slope' get_key trend),(<'relative'),(<relative),<'verdict' get_key trend
    end.
    ReportLines
)
customer_lines =: 3 : 0
    ReportLines =: 0$a:
    for_box. CustomerSummaries do.
        customer =. >box
        offer =. 'offer' get_key customer
        if. #offer do. offer =. itemset_text offer else. offer =. 'none' end.
        add_line (<'CUSTOMER'),(<'customer' get_key customer),(<'baskets'),(<'baskets' get_key customer),(<'days'),(<'days' get_key customer),(<'first'),(<'first' get_key customer),(<'last'),(<'last' get_key customer),(<'items'),(<'products' get_key customer),(<'units'),(<'units' get_key customer),(<'revenue'),(<money_text 'revenue' get_key customer),(<'average'),(<money_text 'average' get_key customer),(<'favorite'),(<'favorite' get_key customer),(<'segment'),(<'segment' get_key customer),(<'offer'),<offer
    end.
    for_segmentbox. Segments do.
        segment =. >segmentbox
        count =. revenue =. 0
        for_box. CustomerSummaries do.
            customer =. >box
            if. segment-:'segment' get_key customer do.
                count =. count+1
                revenue =. revenue+'revenue' get_key customer
            end.
        end.
        add_line (<'SEGMENT'),(<segment),(<'customers'),(<count),(<'revenue'),(<money_text revenue),(<'share'),<revenue percent_text TotalRevenue
    end.
    ReportLines
)
main =: 3 : 0
    read_params ''
    read_dataset ''
    analyze_frequent ''
    analyze_sequences ''
    analyze_validation ''
    analyze_products ''
    analyze_trends ''
    analyze_customers ''
    1!:5 <'output'
    'summary.txt' write_report summary_lines ''
    'itemsets.txt' write_report itemset_lines ''
    'closed_maximal.txt' write_report closed_lines ''
    'rules.csv' write_report rules_csv 'rules' get_key MainRules
    'category_rules.csv' write_report rules_csv 'rules' get_key CategoryRules
    'sequences.txt' write_report sequence_lines ''
    'validation.txt' write_report validation_lines ''
    'items_report.txt' write_report item_lines ''
    'trends.txt' write_report trend_lines ''
    'customers.txt' write_report customer_lines ''
    i.0
)
main ''
