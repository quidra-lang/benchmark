ScriptPath=: >{:4!:3''
SourceDirectory=: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'tac_parser.ijs'
load SourceDirectory,'cfg.ijs'
load SourceDirectory,'dataflow.ijs'
load SourceDirectory,'optimizations.ijs'
load SourceDirectory,'regalloc.ijs'
clone_program=:3 :0
 result=.0$a:
  for_f. y  do.
  g=.cocreate''
  name__g=:name__f
  params__g=:params__f
  code__g=:0$a:
  temp__g=:0
  pre__g=:0
   for_s. code__f  do. code__g=:code__g,clone s  end.
  result=.result,g
  end.
 result
)
call_graph=:3 :0
 fs=.y
  names=.0$a:
  for_f. fs  do. names=.names,<name__f  end.
 adjacency=.((#fs),#fs)$0
  for_i. i.#fs  do. f=.i{fs
   for_s. code__f  do.  if. kind__s-:'call' do. j=.names i.<callee__s
  adjacency=.1 (<i,j)}adjacency  end.  end.
  end.
 closure=.adjacency
  for_k. i.#fs  do.  for_i. i.#fs  do.  if. (<i,k){closure  do. closure=.((i{closure)+.k{closure)i}closure  end.  end.  end.
 reachable=.~.(names i.<'main'),I.(names i.<'main'){closure
 lines=.0$a:
  for_i. i.#fs  do.
  line=.(i{::names),' -> ',','join (I.i{adjacency){names
   if. (<i,i){closure  do. line=.line,' (recursive)' end.
  lines=.lines,<line
  end.
 unreachable=.((i.#fs)-.reachable){names
 lines=.lines,<'unreachable functions: ',','join unreachable
 lines;unreachable
)
rd_string=:3 :0
 ids=.y
  ns=.ids{DefinitionNumbers
  vars=.ids{DefinitionVars
 order=./:vars
  order=.( /:order{ns){order
 parts=.0$a:
  for_i. order  do. parts=.parts,<(i{::vars),':',dec i{ns  end.
 ','join parts
)
expr_string=:3 : ''',''join /:~y{Expressions'
live_string=:3 : ''',''join /:~y'
tree_lines=:4 :0
 b=.y
  depth=.x
 lines=.,<((2*depth)$' '),bname b
  for_child. I.Idom=b  do. lines=.lines,(depth+1)tree_lines child  end.
 lines
)
analysis_lines=:4 :0
 typ=.x
  f=.y
 analyze f
 result=.(<'== ',name__f,' (',typ,') =='),<'code:'
 n=.0
  for_s. code__f  do.
   if. kind__s-:'label' do. result=.result,<instruction_text s
   continue.  end.
  line=.'  #',(dec n+1),' ',instruction_text s
  us=.~.used s
   if. ((n{InsBlock)e.Reachable)*.#us  do.
   chains=.0$a:
    for_v. us  do.
    defs=.i.0
     for_i. n{::RDBefore  do.  if. (>v)-:i{::DefinitionVars  do. defs=.defs,i{DefinitionNumbers  end.  end.
    chains=.chains,<(>v),':',','join dec&.><"0 /:~defs
    end.
   line=.line,' | ',' 'join chains
   end.
  result=.result,<line
  n=.n+1
  end.
 result=.result,<'blocks: ',dec #BlockIns
  for_b. i.#BlockIns  do.
  ns=.b{::BlockIns
  result=.result,<(bname b),' ',(dec 1+{.ns),'-',(dec 1+{:ns),' labels=',(','join b{::BlockLabels),' preds=',(blist b{::Predecessors),' succs=',','join bname&.><"0 b{::Successors
  end.
 result=.result,(<'unreachable: ',blist (i.#BlockIns)-.Reachable),<'order: ',','join bname&.><"0 RPO
 result=.result,<'dominators:'
  for_b. Reachable  do.
  parent=.'-'
   if. b~:0 do. parent=.bname b{Idom  end.
  result=.result,<(bname b),' idom=',parent,' dom=',blist b{::Dominators
  end.
 result=.result,(<'dominator tree:'),0 tree_lines 0
 result=.result,<'loops: ',dec #Loops
  for_l. Loops  do. result=.result,<'header=',(bname header__l),' latches=',(blist latches__l),' depth=',(dec depth__l),' blocks=',(blist blocks__l),' exits=',blist exits__l  end.
 result=.result,<'reaching definitions: iterations=',dec RDIters
  for_b. Reachable  do. result=.result,<(bname b),' in=',(rd_string b{::RDIn),' out=',rd_string b{::RDOut  end.
 result=.result,<'liveness: iterations=',dec LiveIters
  for_b. Reachable  do. result=.result,<(bname b),' in=',(live_string b{::LiveIn),' out=',live_string b{::LiveOut  end.
 result=.result,<'available expressions: iterations=',dec ExprIters
  for_b. Reachable  do. result=.result,<(bname b),' in=',(expr_string b{::ExprIn),' out=',expr_string b{::ExprOut  end.
 result
)
get_value=:4 :0
 env=.x
  if. isconst y  do. num y  else. (keys__env i.<y){values__env  end.
)
set_value=:4 :0
 env=.x
  'name val'=.y
 i=.keys__env i.<name
  if. i=#keys__env  do. keys__env=:keys__env,<name
  values__env=:values__env,val  else. values__env=:val i}values__env  end.
)
execute_function=:4 :0
 f=.x
  argv=.y
 fi=.RuntimeNames i.<name__f
 RunCalls=:(1+fi{RunCalls)fi}RunCalls
 env=.cocreate''
 keys__env=:params__f
  values__env=:argv
 pending=.i.0
  pc=.0
  ins=.0$a:
  labels=.0$a:
  positions=.i.0
  for_s. code__f  do.  if. kind__s-:'label' do. labels=.labels,<target__s
  positions=.positions,#ins  else. ins=.ins,s  end.  end.
  while. pc<#ins  do.
  s=.pc{ins
  pc=.pc+1
  RunSteps=:(1+fi{RunSteps)fi}RunSteps
  ki=.Kinds i.<kind__s
  RunKinds=:(1+ki{RunKinds)ki}RunKinds
   if. #a__s  do. a=.env get_value a__s  end.
   if. #b__s  do. b=.env get_value b__s  end.
   select. kind__s
   case. 'copy' do. env set_value dest__s;a
   case. 'bin' do. env set_value dest__s;op__s operation a,b
   case. 'load' do. i=.ArrayNames i.<array__s
  env set_value dest__s;a{i{::ArrayValues
   case. 'store' do. i=.ArrayNames i.<array__s
  arr=.i{::ArrayValues
  ArrayValues=:(<b a}arr)i}ArrayValues
   case. 'goto' do. pc=.(labels i.<target__s){positions
   case. 'if' do.  if. op__s operation a,b  do. pc=.(labels i.<target__s){positions  end.
   case. 'param' do. pending=.pending,a
   case. 'call' do.
   n=.count__s
  args=.(-n){.pending
    if. n=0 do. args=.i.0 else. pending=.(-n)}.pending  end.
   target=.(RuntimeNames i.<callee__s){RuntimeProgram
   val=.target execute_function args
    if. #dest__s  do. env set_value dest__s;val  end.
   case. 'return' do.  if. #a__s  do. a  return.  else. 0 return.  end.
   case. 'read' do. env set_value dest__s;RunInputPosition{RunInput
  RunInputPosition=:RunInputPosition+1
   case. 'print' do. RunOutput=:RunOutput,a
   end.
  end.
 0
)
execute_program=:4 :0
 RuntimeProgram=:x
  RunInput=:y
 RuntimeNames=:0$a:
  for_f. x  do. RuntimeNames=:RuntimeNames,<name__f  end.
 ArrayNames=:0$a:
  ArrayValues=:0$a:
  for_arr. Arrays  do. 'name size'=.>arr
  ArrayNames=:ArrayNames,<name
  ArrayValues=:ArrayValues,<size$0 end.
 RunSteps=:RunCalls=:(#x)$0
  RunKinds=:11$0
  RunOutput=:i.0
  RunInputPosition=:0
 f=.(RuntimeNames i.<'main'){x
 f execute_function i.0
 RunSteps;RunCalls;RunKinds;RunOutput
)
kind_counts=:3 :0
 result=.11$0
  for_f. y  do.  for_s. code__f  do. i=.Kinds i.<kind__s
   if. i<11 do. result=.(1+i{result)i}result  end.  end.  end.
 result
)
main=:3 :0
 params=.readlines 'input/params.txt'
 Registers=:num 1{::words 0{::params
 Enabled=:((<;._1 ' ','constprop copyprop cse dce licm unreachable'))intersect }.words 1{::params
 MaxRounds=:num 1{::words 2{::params
 Original=:parse_program readlines 'input/program.tac'
 Optimized=:clone_program Original
 Analysis=.,<'== call graph (original) =='
 'graph unused'=.call_graph Original
  Analysis=.Analysis,graph
  for_f. Original  do. Analysis=.Analysis,'original'analysis_lines f  end.
 Passes=.0$a:
  TotalChanges=:(#Enabled)$0
  for_f. Optimized  do.
  initial=.0
   for_s. code__f  do. initial=.initial+-.kind__s-:'label' end.
  Passes=.Passes,<'== ',name__f,' =='
   for_round. 1+i.MaxRounds  do.
   counts=.i.0
  records=.0$a:
    for_pi. i.#Enabled  do.
    pname=.pi{::Enabled
    analyze f
     select. pname
     case. 'constprop' do. constant_pass f
     case. 'copyprop' do. copy_pass f
     case. 'cse' do. cse_pass f
     case. 'dce' do. dce_pass f
     case. 'licm' do. licm_pass f
     case. 'unreachable' do. unreachable_pass f
     end.
    counts=.counts,PassCount
     for_record. PassRecords  do. records=.records,<'  ',pname,' ',>record  end.
    end.
   fields=.0$a:
    for_pi. i.#Enabled  do. fields=.fields,<(pi{::Enabled),'=',dec pi{counts  end.
   Passes=.Passes,(<'round ',(dec round),': ',' 'join fields),records
   TotalChanges=:TotalChanges+counts
    if. 0=+/counts  do.  break.  end.
   end.
  final=.0
   for_s. code__f  do. final=.final+-.kind__s-:'label' end.
  Passes=.Passes,<'result: rounds=',(dec round),' instructions=',(dec initial),'->',dec final
  end.
 Analysis=.Analysis,<'== call graph (optimized) =='
 'graph unused'=.call_graph Optimized
  Analysis=.Analysis,graph
 removed=.0$a:
  if. (<'unreachable')e.Enabled  do. removed=.unused
  keep=.i.0
   for_i. i.#Optimized  do. f=.i{Optimized
   if. -.(<name__f)e.removed  do. keep=.keep,i  end.  end.
  Optimized=:keep{Optimized  end.
  for_f. Optimized  do. Analysis=.Analysis,'optimized'analysis_lines f  end.
 totals=.0$a:
  for_i. i.#Enabled  do. totals=.totals,<(i{::Enabled),'=',dec i{TotalChanges  end.
 Passes=.Passes,(<'== program =='),(<'removed functions: ',','join removed),(<'== total =='),<' 'join totals
 Allocated=:0$a:
  Allocation=.0$a:
  for_f. Optimized  do. 'g report'=.Registers allocate f
  Allocated=:Allocated,g
  Allocation=.Allocation,report  end.
 'output/optimized.tac'write_lines program_lines Optimized
 'output/analysis.txt'write_lines Analysis
 'output/passes.txt'write_lines Passes
 'output/regalloc.txt'write_lines Allocation
 input=.readlines 'input/input.txt'
 Comparisons=.0$a:
  Same=.0
  StepTotals=.3$0
  KindTotals=.3 11$0
 FunctionSteps=.((#Original),3)$0
  FunctionCalls=.(#Original)$0
 programs=.Original;Optimized;Allocated
  for_ri. i.num 0{::input  do.
  values=.num >words (ri+1){::input
  values=.}.values
  Comparisons=.Comparisons,<'run ',(dec ri+1),': inputs=',dec #values
  outputs=.0$a:
   for_p. i.3 do.
   program=.p{::programs
   'steps calls kinds output'=.program execute_program values
   outputs=.outputs,<output
   label=.p{::'original';'optimized';'allocated'
   Comparisons=.Comparisons,<'  ',label,': steps=',(dec +/steps),' calls=',(dec +/calls),' output=',','join dec&.><"0 output
   StepTotals=:( (+/steps)+p{StepTotals)p}StepTotals
   KindTotals=:(kinds+p{KindTotals)p}KindTotals
    for_j. i.#Original  do.
    orig=.j{Original
  idx=.RuntimeNames i.<name__orig
     if. idx<#program  do. FunctionSteps=:(((<j,p){FunctionSteps)+idx{steps)(<j,p)}FunctionSteps
   if. p=0 do. FunctionCalls=:((idx{calls)+j{FunctionCalls)j}FunctionCalls  end.  end.
    end.
   end.
  same=.(0{::outputs)-:1{::outputs
  same=.same*.(0{::outputs)-:2{::outputs
  Same=.Same+same
  Comparisons=.Comparisons,<'  result: ',('different';'same'){::~same
  end.
 Comparisons=.Comparisons,<'== profile =='
  for_i. i.#Original  do. f=.i{Original
  row=.i{FunctionSteps
  Comparisons=.Comparisons,<name__f,': calls=',(dec i{FunctionCalls),' original=',(dec 0{row),' optimized=',(dec 1{row),' allocated=',dec 2{row  end.
 N=.<:#input
 oc=.kind_counts Original
  nc=.kind_counts Optimized
 fields=.0$a:
  for_i. i.11 do. fields=.fields,<(i{::Kinds),'=',(dec i{oc),'->',dec i{nc  end.
 Comparisons=.Comparisons,(<'== summary =='),(<'runs=',(dec N),' same=',(dec Same),' different=',dec N-Same),(<'instructions: original=',(dec +/oc),' optimized=',dec +/nc),(<'kinds: ',' 'join fields),<'steps: original=',(dec 0{StepTotals),' optimized=',(dec 1{StepTotals),' allocated=',dec 2{StepTotals
  for_p. i.3 do.
  fields=.0$a:
   for_i. i.11 do. fields=.fields,<(i{::Kinds),'=',dec (<p,i){KindTotals  end.
  Comparisons=.Comparisons,<'dynamic ',(p{::'original';'optimized';'allocated'),': ',' 'join fields
  end.
 'output/comparison.txt'write_lines Comparisons
 0
)
main''
