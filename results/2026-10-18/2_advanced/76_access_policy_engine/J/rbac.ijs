roles_by_name =: 3 : 'y /:y{RoleNames'
role_closure =: 3 : 0
    reached =. (#RoleNames)$0
    pending =. y
    while. #pending do.
        role =. {:pending
        pending =. }:pending
        if. -.role{reached do.
            reached =. 1 role}reached
            pending =. pending,role{::Inheritance
        end.
    end.
    I.reached
)
role_path =: 4 : 0
    if. x=y do.
        ,x return.
    end.
    for_junior. roles_by_name x{::Inheritance do.
        if. y e.role_closure ,junior do.
            x,junior role_path y return.
        end.
    end.
    i.0
)
assigned_roles =: 4 : 0
    roles =. i.0
    for_assignment. Assignments do.
        'owner role first last' =. >assignment
        if. (x-:owner)*.(y>:first)*.y<:last do.
            roles =. roles,role
        end.
    end.
    ~.roles
)
authorized_roles =: 4 : 'role_closure x assigned_roles y'
accept_rbac =: 4 : 0
    keyword =. x
    fields =. y
    select. keyword
    case. 'ROLE' do.
        role =. 0{::fields
        if. (<role)e.RoleNames do.
            'duplicate role ',role return.
        end.
        RoleNames =: RoleNames,<role
        Inheritance =: Inheritance,<i.0
        RolePermissions =: RolePermissions,<0$a:
    case. 'INHERITS' do.
        'senior_name junior_name' =. fields
        senior =. RoleNames i.<senior_name
        junior =. RoleNames i.<junior_name
        if. senior=#RoleNames do.
            'unknown role ',senior_name return.
        end.
        if. junior=#RoleNames do.
            'unknown role ',junior_name return.
        end.
        if. junior e.senior{::Inheritance do.
            'duplicate inheritance ',senior_name,' ',junior_name return.
        end.
        if. senior e.role_closure ,junior do.
            path =. senior,junior role_path senior
            'cycle ',' > 'join path{RoleNames return.
        end.
        Inheritance =: (<(senior{::Inheritance),junior)senior}Inheritance
    case. 'PERMIT' do.
        'role_name action kind' =. fields
        role =. RoleNames i.<role_name
        if. role=#RoleNames do.
            'unknown role ',role_name return.
        end.
        permission =. action,' ',kind
        if. (<permission)e.role{::RolePermissions do.
            'duplicate permission ',role_name,' ',permission return.
        end.
        RolePermissions =: (<(role{::RolePermissions),<permission)role}RolePermissions
        Grants =: Grants,<role;action;kind
    case. 'SSD';'DSD' do.
        'name cardinality role_list' =. fields
        constraints =. SSDConstraints
        if. keyword-:'DSD' do.
            constraints =. DSDConstraints
        end.
        for_constraint. constraints do.
            if. name-:0{::>constraint do.
                'duplicate constraint ',name return.
            end.
        end.
        roles =. i.0
        for_role_name. split_commas role_list do.
            role =. RoleNames i.role_name
            if. role=#RoleNames do.
                'unknown role ',>role_name return.
            end.
            roles =. roles,role
        end.
        cardinality =. parse_int cardinality
        if. (cardinality<2)+.cardinality>#roles do.
            'bad cardinality ',name,' ',integer cardinality return.
        end.
        constraint =. (<name),(<cardinality),<roles
        if. keyword-:'SSD' do.
            SSDConstraints =: SSDConstraints,<constraint
        else.
            DSDConstraints =: DSDConstraints,<constraint
        end.
    case. 'ASSIGN' do.
        'user role_name first last' =. fields
        role =. RoleNames i.<role_name
        if. role=#RoleNames do.
            'unknown role ',role_name return.
        end.
        first =. parse_int first
        last =. parse_int last
        if. (first<1)+.(last>365)+.first>last do.
            'bad range ',(integer first),' ',integer last return.
        end.
        for_constraint. SSDConstraints do.
            'name cardinality roles' =. >constraint
            for_day. first+i.1+last-first do.
                closure =. role_closure role,user assigned_roles day
                intersection =. roles#~roles e.closure
                if. cardinality<:#intersection do.
                    names =. (roles_by_name intersection){RoleNames
                    'ssd ',name,' day ',(integer day),' roles ',(','join names) return.
                end.
            end.
        end.
        Assignments =: Assignments,<user;role;first;last
    end.
    ''
)
read_rbac =: 3 : 0
    RoleNames =: 0$a:
    Inheritance =: 0$a:
    RolePermissions =: 0$a:
    SSDConstraints =: 0$a:
    DSDConstraints =: 0$a:
    Assignments =: 0$a:
    RBACDiagnostics =: 0$a:
    Grants =: 0$a:
    rows =. read_lines 'input/rbac.txt'
    for_keyword. 'ROLE';'INHERITS';'PERMIT';'SSD';'DSD';'ASSIGN' do.
        keyword =. >keyword
        for_i. i.#rows do.
            fields =. split_words i{::rows
            if. keyword-:0{::fields do.
                error =. keyword accept_rbac }.fields
                if. #error do.
                    RBACDiagnostics =: RBACDiagnostics,<(i+1);keyword;error
                end.
            end.
        end.
    end.
    numbers =. i.0
    for_diagnostic. RBACDiagnostics do.
        numbers =. numbers,0{::>diagnostic
    end.
    RBACDiagnostics =: (/:numbers){RBACDiagnostics
    i.0
)
