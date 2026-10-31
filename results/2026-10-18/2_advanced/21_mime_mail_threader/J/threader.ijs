new_container =: 3 : 0
    index =. #ContainerIds
    ContainerIds =: ContainerIds,<y
    ContainerMessages =: ContainerMessages,_1
    ContainerParents =: ContainerParents,_1
    ContainerChildren =: ContainerChildren,<0$0
    ContainerSubjects =: ContainerSubjects,<''
    index
)
container_of =: 3 : 0
    position =. RegisteredIds i.<y
    if. position<#RegisteredIds do. position{RegisteredContainers return. end.
    index =. new_container y
    RegisteredIds =: RegisteredIds,<y
    RegisteredContainers =: RegisteredContainers,index
    index
)
is_ancestor =: 4 : 0
    while. y>:0 do.
        if. x=y do. 1 return. end.
        y =. y{ContainerParents
    end.
    0
)
adopt =: 4 : 0
    ContainerParents =: x y}ContainerParents
    ContainerChildren =: (<(x{::ContainerChildren),y)x}ContainerChildren
    i.0
)
prune_containers =: 4 : 0
    result =. 0$0
    for_container. y do.
        children =. 0 prune_containers container{::ContainerChildren
        ContainerChildren =: (<children)container}ContainerChildren
        if. ((container{ContainerMessages)>:0)+.x*.2<:#children do. result =. result,container
        else.
            parent =. container{ContainerParents
            if. x do. parent =. _1 end.
            ContainerParents =: parent children}ContainerParents
            result =. result,children
        end.
    end.
    result
)
container_key =: 3 : 0
    message =. y{ContainerMessages
    if. message>:0 do. message{MessageRanks return. end.
    best =. #Messages
    for_child. y{::ContainerChildren do. best =. best<.container_key child end.
    best
)
sort_containers =: 3 : 0
    keys =. 0$0
    for_container. y do.
        children =. sort_containers container{::ContainerChildren
        ContainerChildren =: (<children)container}ContainerChildren
        keys =. keys,container_key container
    end.
    (/:keys){y
)
root_subject =: 3 : 0
    message =. y{ContainerMessages
    if. message<0 do. child =. {.y{::ContainerChildren
        message =. child{ContainerMessages end.
    6{::message{::Messages
)
build_threads =: 3 : 0
    ContainerIds =: ContainerChildren =: ContainerSubjects =: RegisteredIds =: 0$a:
    ContainerMessages =: ContainerParents =: RegisteredContainers =: 0$0
    ids =. 0$a:
    dates =. 0$0
    for_index. i.#Messages do.
        message =. index{::Messages
        id =. 0{::message
        ids =. ids,<id
        dates =. dates,1{::message
        if. #id do. container =. container_of id
        else. container =. new_container '' end.
        ContainerMessages =: index container}ContainerMessages
        references =. 0$0
        for_reference. 8{::message do. references =. references,container_of >reference end.
        for_position. i.0>.(#references)-1 do.
            current =. position{references
            following =. (position+1){references
            if. (_1=following{ContainerParents)*.-.following is_ancestor current do. current adopt following end.
        end.
        parent =. container{ContainerParents
        if. parent>:0 do.
            siblings =. parent{::ContainerChildren
            ContainerChildren =: (<siblings#~siblings~:container)parent}ContainerChildren
            ContainerParents =: _1 container}ContainerParents
        end.
        if. #references do.
            last =. {:references
            if. -.container is_ancestor last do. last adopt container end.
        end.
    end.
    idranks =. /:ascii_order ids
    order =. /:(dates<0),.(0>.dates),.idranks,.i.#Messages
    MessageRanks =: /:order
    roots =. 1 prune_containers I.ContainerParents=_1
    roots =. sort_containers roots
    subjects =. 0$a:
    groups =. 0$a:
    for_root. roots do.
        subject =. root_subject root
        if. 0=#subject do. continue. end.
        group =. subjects i.<subject
        if. group=#subjects do.
            subjects =. subjects,<subject
            groups =. groups,<,root
        else. groups =. (<(group{::groups),root)group}groups end.
    end.
    merged =. 0$0
    for_root. roots do.
        subject =. root_subject root
        if. 0=#subject do. merged =. merged,root
        else.
            group =. subjects i.<subject
            if. 1=#group{::groups do. merged =. merged,root end.
        end.
    end.
    for_index. i.#groups do.
        group =. index{::groups
        if. (#group)<2 do. continue. end.
        missing =. group#~(group{ContainerMessages)<0
        originals =. 0$0
        for_root. group do.
            message =. root{ContainerMessages
            if. message>:0 do.
                if. -.7{::message{::Messages do. originals =. originals,root end.
            end.
        end.
        if. #missing do. target =. {.missing
        elseif. (#originals)=1 do. target =. {.originals
        else.
            target =. new_container ''
            ContainerSubjects =: (index{subjects)target}ContainerSubjects
        end.
        for_root. group do.
            if. root=target do. continue. end.
            if. (root{ContainerMessages)>:0 do. target adopt root
            else. for_child. root{::ContainerChildren do. target adopt child end. end.
        end.
        merged =. merged,target
    end.
    sort_containers merged
)
