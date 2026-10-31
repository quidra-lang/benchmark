need =: 4 : 0
    multiplier =. ('qty_per' get_key x)*100+'scrap' get_key x
    ((y*multiplier)+99) div 100
)
search_path =: 3 : 0
    if. y-:SearchTarget do. <y return. end.
    SearchVisited =: SearchVisited,<y
    for_box. y get_key Children do.
        child =. 'child' get_key >box
        if. (<child)e.SearchVisited do. continue. end.
        rest =. search_path child
        if. #rest do. (<y),rest return. end.
    end.
    0$a:
)
read_bom =: 3 : 0
    Children =: Parents =: empty_table ''
    for_idbox. table_keys Items do.
        Children =: (idbox,<0$a:) put_key Children
        Parents =: (idbox,<0$a:) put_key Parents
    end.
    for_box. read_rows 'bom.csv' do.
        'line fields' =. >box
        'parent child quantitytext scraptext' =. fields
        quantity =. num quantitytext
        scrap =. num scraptext
        reason =. ''
        if. -.parent has_key Items do. reason =. 'unknown item ',parent
        elseif. -.child has_key Items do. reason =. 'unknown item ',child
        elseif. quantity<1 do. reason =. 'bad quantity ',number quantity
        elseif. scrap>50 do. reason =. 'bad scrap ',number scrap
        elseif. parent-:child do. reason =. 'cycle ',parent,' -> ',parent
        else.
            for_rowbox. parent get_key Children do.
                if. child-:'child' get_key >rowbox do. reason =. 'duplicate ',parent,' -> ',child
                break. end.
            end.
            if. 0=#reason do.
                SearchTarget =: parent
                SearchVisited =: 0$a:
                path =. search_path child
                if. #path do. reason =. 'cycle ',parent,' -> ',' -> ' join path end.
            end.
        end.
        if. #reason do. 'bom.csv' record_error (<line),<reason
        else.
            row =. 'parent child qty_per scrap' record (<parent),(<child),(<quantity),<scrap
            children =. 'child' sort_records (parent get_key Children),<row
            parents =. 'parent' sort_records (child get_key Parents),<row
            Children =: ((<parent),<children) put_key Children
            Parents =: ((<child),<parents) put_key Parents
        end.
    end.
    i.0
)
low_code =: 3 : 0
    if. y has_key LowCodes do. y get_key LowCodes return. end.
    value =. 0
    for_box. y get_key Parents do. value =. value>.1+low_code 'parent' get_key >box end.
    LowCodes =: ((<y),<value) put_key LowCodes
    value
)
cumulative_lead =: 3 : 0
    if. y has_key Cumulative do. y get_key Cumulative return. end.
    longest =. 0
    for_box. y get_key Children do. longest =. longest>.cumulative_lead 'child' get_key >box end.
    value =. longest+'lead_time' get_key y get_key Items
    Cumulative =: ((<y),<value) put_key Cumulative
    value
)
analyze_bom =: 3 : 0
    LowCodes =: Cumulative =: empty_table ''
    for_box. ItemIds do.
        low_code >box
        cumulative_lead >box
    end.
    codes =. 0$0
    for_box. ItemIds do. codes =. codes,(>box) get_key LowCodes end.
    PlanningOrder =: (/:codes,.i.#codes){ItemIds
    i.0
)
