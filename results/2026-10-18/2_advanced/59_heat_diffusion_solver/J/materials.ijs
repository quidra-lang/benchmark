read_materials =: 3 : 0
    rows =. read_lines 'materials.txt'
    codes =. ''
    names =. 0$a:
    values =. 0 3$0.0
    for_row. rows do.
        fields =. split_words >row
        codes =. codes,{.0{::fields
        names =. names,1{fields
        values =. values,0.0+".&>2}.fields
    end.
    (<codes),(<names),<values
)
heat_capacity =: 4 : 0
    'k rho cp' =. x
    'dx thickness' =. y
    (((rho*cp)*dx)*dx)*thickness
)
interior_conductance =: 4 : 0
    'first second' =. x
    (((2.0*first)*second)%(first+second))*y
)
fixed_conductance =: 4 : '(2.0*x)*y'
convective_conductance =: 4 : 0
    'h dx thickness' =. y
    first =. 1.0%((h*dx)*thickness)
    second =. 1.0%((2.0*x)*thickness)
    1.0%(first+second)
)
