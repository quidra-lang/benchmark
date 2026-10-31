product_record =: 3 : '''name category price'' record y'
transaction_record =: 3 : '''tid customer day counts'' record y,<empty_table '''''
read_records =: 3 : 0
    rows =. 0$a:
    for_box. }.read_lines y do. rows =. rows,<',' split >box end.
    rows
)
basket_items =: 3 : '/:~table_keys ''counts'' get_key y'
extended_basket =: 4 : 0
    found =. y
    for_box. y do. found =. found,< (>box) get_key x end.
    /:~~.found
)
contains =: 4 : '*./y e.x'
add_product =: 4 : 0
    counts =. ((<x),<1) increment_key 'counts' get_key y
    ((<'counts'),<counts) put_key y
)
