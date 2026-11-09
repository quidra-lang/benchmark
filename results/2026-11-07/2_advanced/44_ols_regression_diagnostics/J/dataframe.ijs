read_lines =: 3 : '<;._2 (1!:1 <y)'
decimal =: 3 : 0
    value =. y
    value =. '_'(I.value='-')}value
    0.0+0".value
)
df_columns =: 0&{::
df_categorical =: 1&{::
df_rows =: 2&{::
read_csv =: 4 : 0
    lines =. read_lines y
    columns =. <;._1 ',',0{::lines
    rows =. (0,#columns)$a:
    for_line. }.lines do.
        rows =. rows,<;._1 ',',>line
    end.
    kinds =. (#columns)$0
    for_column. i.#columns do.
        categorical =. 0
        if. #x do.
            original =. (df_columns x)i.column{columns
            categorical =. original{df_categorical x
        else.
            for_box. column{"1 rows do.
                value =. >box
                if. (-.'NA'-:value)*.({.value)e.'ABCDEFGHIJKLMNOPQRSTUVWXYZ' do.
                    categorical =. 1
                end.
            end.
        end.
        kinds =. categorical column}kinds
    end.
    (<columns),(<kinds),<rows
)
read_params =: 3 : 0
    values =. i.0
    for_line. read_lines 'input/params.txt' do.
        fields =. <;._1 ' ',>line
        values =. values,decimal&>}.fields
    end.
    values
)
