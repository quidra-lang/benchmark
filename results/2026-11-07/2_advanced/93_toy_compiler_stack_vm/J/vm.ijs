trunc_div =: 4 : 0
    quotient =. <.(x:|x)%x:|y
    if. (x<0)~:y<0 do. -quotient else. quotient end.
)
calculate =: 3 : 0
    'op a b' =. y
    if. ((<op)e.'DIV';'MOD')*.b=0 do. (<0x),<'division by zero' return. end.
    select. op
    case. 'ADD' do. result =. a+b
    case. 'SUB' do. result =. a-b
    case. 'MUL' do. result =. a*b
    case. 'DIV' do. result =. a trunc_div b
    case. 'MOD' do. result =. a-b*a trunc_div b
    case. 'NEG' do. result =. -a
    case. 'NOT' do. result =. a=0
    case. 'LT' do. result =. a<b
    case. 'LE' do. result =. a<:b
    case. 'GT' do. result =. a>b
    case. 'GE' do. result =. a>:b
    case. 'EQ' do. result =. a=b
    case. 'NE' do. result =. a~:b
    end.
    if. (result<_2147483648x)+.result>2147483647x do.
        (<0x),<'integer overflow'
    else.
        (<result),<''
    end.
)
vm_pop =: 3 : 0
    value =. {:VmStack
    VmStack =: }:VmStack
    value
)
vm_step =: 3 : 0
    'op args position' =. VmPC{::VmCode
    next =. VmPC+1
    select. op
    case. 'PUSH' do. VmStack =: VmStack,{.args
    case. 'POP' do. vm_pop ''
    case. 'LOADG' do. VmStack =: VmStack,({.args){VmGlobals
    case. 'STOREG' do. VmGlobals =: (vm_pop '')({.args)}VmGlobals
    case. 'LOADL';'STOREL';'ENTER' do.
        last =. (#VmFrames)-1
        'locals return_address' =. last{::VmFrames
        if. op-:'LOADL' do.
            VmStack =: VmStack,({.args){locals
        elseif. op-:'STOREL' do.
            locals =. (vm_pop '')({.args)}locals
        else.
            locals =. locals,(({.args)-#locals)$0x
        end.
        VmFrames =: (<(<locals),<return_address)last}VmFrames
    case. 'LOADA';'STOREA' do.
        if. op-:'STOREA' do. value =. vm_pop '' end.
        index =. vm_pop ''
        'address size' =. args
        if. (index<0)+.index>:size do.
            VmError =: 'index ',(integer index),' out of bounds for array of size ',integer size
            0 return.
        end.
        if. op-:'LOADA' do. VmStack =: VmStack,(address+index){VmGlobals
        else. VmGlobals =: value(address+index)}VmGlobals end.
    case. 'ADD';'SUB';'MUL';'DIV';'MOD';'LT';'LE';'GT';'GE';'EQ';'NE' do.
        b =. vm_pop ''
        a =. vm_pop ''
        'value error' =. calculate(<op),(<a),<b
        if. #error do.
            VmError =: error
            0 return.
        end.
        VmStack =: VmStack,value
    case. 'NEG';'NOT' do.
        a =. vm_pop ''
        'value error' =. calculate(<op),(<a),<0
        if. #error do.
            VmError =: error
            0 return.
        end.
        VmStack =: VmStack,value
    case. 'JUMP' do. next =. {.args
    case. 'JUMPF';'JUMPT' do.
        value =. vm_pop ''
        if. (value=0)=op-:'JUMPF' do. next =. {.args end.
    case. 'CALL' do.
        if. 100=#VmFrames do.
            VmError =: 'call depth limit exceeded'
            0 return.
        end.
        'target count' =. args
        locals =. 0$0x
        if. count do.
            locals =. (-count){.VmStack
            VmStack =: (-count)}.VmStack
        end.
        VmFrames =: VmFrames,<(<locals),<next
        callee =. target{VmStarts
        caller =. VmPC{VmOwners
        VmCalls =: (1+callee{VmCalls)callee}VmCalls
        cell =. <caller,callee
        VmPairs =: (1+cell{VmPairs)cell}VmPairs
        next =. target
    case. 'RET';'RETV' do.
        next =. 1{::_1{::VmFrames
        VmFrames =: }:VmFrames
    case. 'READ' do.
        if. VmRead=#VmInputs do.
            VmError =: 'read past end of input'
            0 return.
        end.
        VmStack =: VmStack,VmRead{VmInputs
        VmRead =: VmRead+1
    case. 'PRINT' do.
        count =. {.args
        values =. (-count){.VmStack
        VmStack =: (-count)}.VmStack
        VmOutput =: VmOutput,<' 'join integer&.>values
    end.
    VmMaxStack =: VmMaxStack>.#VmStack
    VmMaxDepth =: VmMaxDepth>.#VmFrames
    VmPC =: next
    -.op-:'HALT'
)
run_vm =: 3 : 0
    'VmCode VmOwners VmStarts global_size VmInputs' =: y
    VmGlobals =: global_size$0x
    VmStack =: 0$0x
    VmFrames =: VmOutput =: 0$a:
    VmRead =: VmPC =: VmExecuted =: VmMaxStack =: VmMaxDepth =: 0
    VmCounts =: (#VmCode)$0
    units =. 1+>./VmOwners
    VmCalls =: units$0
    VmPairs =: (units,units)$0
    VmError =: ''
    while. 1 do.
        if. VmExecuted=100000 do.
            VmError =: 'instruction limit exceeded'
            break.
        end.
        VmExecuted =: VmExecuted+1
        VmCounts =: (1+VmPC{VmCounts)VmPC}VmCounts
        if. -.vm_step '' do. break. end.
    end.
    error_pc =. _1
    if. #VmError do. error_pc =. VmPC end.
    result =. (<VmOutput),(<VmError),(<error_pc),(<VmFrames),(<VmExecuted),(<VmCounts)
    result,(<VmCalls),(<VmPairs),(<VmMaxStack),<VmMaxDepth
)
