TYPES = %w[AND OR NAND NOR XOR XNOR NOT BUF MUX2 DFF].freeze
COUNTS = %w[BUILD:1 RESET:0 SET:3 APPLY:2 PULSE:3 CLOCK:4 RUN:1 WATCH:1 UNWATCH:1 SHOW:0 CHECK:2 PROBE:1 WAVE:2 HISTORY:1 ACTIVITY:1 STATUS:0 MODULES:0 NETLIST:1 HIERARCHY:1 STATS:1 TRUTHTABLE:1 EQUIV:2 FAULTS:1 CRITICAL:1 PERIOD:1].to_h { |x| k,v=x.split(':'); [k,v.to_i] }
SIM = %w[RESET SET APPLY PULSE CLOCK RUN WATCH UNWATCH SHOW CHECK PROBE WAVE HISTORY ACTIVITY STATUS].freeze
Gate = Struct.new(:name,:kind,:inputs,:output,:delay)
Instance = Struct.new(:name,:mod,:connections)
Mod = Struct.new(:name,:inputs,:outputs,:body)
def name?(s) = /\A[a-z][a-z0-9_]{0,15}\z/.match?(s)
def number?(s) = /\A(?:0|[1-9][0-9]{0,8})\z/.match?(s)
def number(s,positive=false)
  raise "bad number #{s}" unless number?(s) && (!positive || s!='0')
  s.to_i
end
def value(s)
  raise "bad value #{s}" unless %w[0 1 X].include?(s)
  s
end
def bits(r,n) = n.times.map { |i| ((r>>(n-1-i))&1).to_s }.join
def logic(kind,a)
  y = case kind
      when 'AND','NAND' then a.include?('0') ? '0' : a.include?('X') ? 'X' : '1'
      when 'OR','NOR' then a.include?('1') ? '1' : a.include?('X') ? 'X' : '0'
      when 'XOR','XNOR' then a.include?('X') ? 'X' : (a.count('1')%2).to_s
      when 'MUX2' then a[0]=='X' ? (a[1]==a[2] ? a[1] : 'X') : a[a[0]=='0' ? 1 : 2]
      else a[0]
      end
  %w[NAND NOR XNOR NOT].include?(kind) ? {'0'=>'1','1'=>'0','X'=>'X'}[y] : y
end
class Circuit
  attr_reader :name,:inputs,:outputs,:gates,:signals,:driver,:readers,:flops,:order
  def initialize(mod)
    @name,@inputs,@outputs=mod.name,mod.inputs,mod.outputs
    @gates=[]
    expand(mod,'',{})
    @signals=@inputs+@gates.map(&:output)
    @driver=@gates.to_h { |g| [g.output,g] }
    @readers=@signals.to_h { |s| [s,[]] }
    @gates.each { |g| g.inputs.uniq.each { |s| @readers[s]<<g } }
    @flops=@gates.select { |g| g.kind=='DFF' }
    waiting={}; ready=[]
    @gates.each do |g|
      next if g.kind=='DFF'
      waiting[g.output]=g.inputs.uniq.count { |s| @driver.key?(s) && @driver[s].kind!='DFF' }
      ready<<g if waiting[g.output]==0
    end
    @order=[]
    until ready.empty?
      g=ready.pop; @order<<g
      @readers[g.output].each do |r|
        next if r.kind=='DFF'
        waiting[r.output]-=1
        ready<<r if waiting[r.output]==0
      end
    end
    @order=nil if @order.size!=waiting.size
  end
  def expand(mod,prefix,ports)
    actual=->(s) { ports.fetch(s,prefix+s) }
    mod.body.each do |x|
      if x.is_a?(Gate)
        @gates<<Gate.new(prefix+x.name,x.kind,x.inputs.map(&actual),actual.call(x.output),x.delay)
      else
        expand(x.mod,prefix+x.name+'.',x.connections.to_h { |p,s| [p,actual.call(s)] })
      end
    end
  end
  def combinational
    raise "#{@name} is not combinational" unless @flops.empty?
    raise "#{@name} has a combinational loop" unless @order
    raise "too many inputs #{@inputs.size}" if @inputs.size>8
    self
  end
  def evaluate(b,stuck=nil,v=nil)
    values=@inputs.zip(b.chars).to_h
    values[stuck]=v if values.key?(stuck)
    @order.each { |g| values[g.output]=g.output==stuck ? v : logic(g.kind,g.inputs.map { |s| values[s] }) }
    @outputs.map { |s| values[s] }.join
  end
  def arrivals(period)
    late=period ? @flops.to_h { |g| [g.output,g.delay] } : @inputs.to_h { |s| [s,0] }
    early=late.dup; prev={}
    @order.each do |g|
      a=g.inputs.select { |s| late.key?(s) }; next if a.empty?
      best=a.max_by { |s| late[s] }
      late[g.output]=late[best]+g.delay; early[g.output]=a.map { |s| early[s] }.min+g.delay; prev[g.output]=best
    end
    [late,early,prev]
  end
end
class Simulation
  attr_accessor :watch,:values,:time,:queue,:history,:processed,:halted
  attr_reader :circuit
  def initialize(c)
    @circuit=c; @watch=[]; reset
  end
  def reset
    @values=@circuit.signals.to_h { |s| [s,'X'] }; @time=0; @queue=[]; @sequence=0
    @history=@circuit.signals.to_h { |s| [s,[]] }; @processed=0; @halted=false
  end
  def schedule(t,s,v)
    e=[t,@sequence,s,v]; @sequence+=1; i=@queue.size; @queue<<e
    while i>0
      p=(i-1)/2; break if (@queue[p][0,2]<=>e[0,2])<=0
      @queue[i]=@queue[p]; i=p
    end
    @queue[i]=e
  end
  def pop
    result=@queue[0]; last=@queue.pop
    unless @queue.empty?
      i=0
      while 2*i+1<@queue.size
        j=2*i+1
        j+=1 if j+1<@queue.size && (@queue[j+1][0,2]<=>@queue[j][0,2])<0
        break if (last[0,2]<=>@queue[j][0,2])<=0
        @queue[i]=@queue[j]; i=j
      end
      @queue[i]=last
    end
    result
  end
  def run(ending)
    total=0; glitches=0
    while !@queue.empty? && @queue[0][0]<ending
      t=@queue[0][0]; start=@values.dup; changed=[]; count=0
      while !@queue.empty? && @queue[0][0]==t
        if count==1000
          puts "halted: oscillation at time #{t}"; @queue=[]; @time=t; @halted=true; return
        end
        _,_,s,v=pop; count+=1; @processed+=1; old=@values[s]; next if old==v
        @values[s]=v; changed<<s
        @circuit.readers[s].each do |g|
          if g.kind!='DFF'
            schedule(t+g.delay,g.output,logic(g.kind,g.inputs.map { |x| @values[x] }))
          elsif s==g.inputs[0] && old=='0' && v=='1'
            schedule(t+g.delay,g.output,@values[g.inputs[1]])
          end
        end
      end
      total+=count
      changed.uniq.each { |s| @values[s]==start[s] ? glitches+=1 : @history[s]<<[t,@values[s]] }
      @watch.each { |s| puts "#{t} #{s} #{@values[s]}" if @values[s]!=start[s] }
    end
    @time=ending; puts "run #{ending} events #{total} glitches #{glitches} pending #{@queue.size}"
  end
  def describe(a) = a.map { |s| "#{s}=#{@values[s]}" }
end
class Simulator
  def initialize = (@modules={}; @sim=nil)
  def lookup(s) = @modules.fetch(s) { raise "unknown module #{s}" }
  def signal(s) = (raise "unknown signal #{s}" unless @sim.values.key?(s))
  def input(s) = (raise "not an input #{s}" unless @sim.circuit.inputs.include?(s))
  def time(w)
    t=number(w); raise "time #{t} is in the past" if t<@sim.time; t
  end
  def define(header_no,lines)
    line_no=header_no
    begin
      w=lines[0].split(' ')
      raise 'bad module header' unless w.size>=5 && w[2]=='IN' && w[3..].count('OUT')==1 && w[-1]!='OUT'
      name=w[1]; raise "bad module name #{name}" unless /\A[A-Z][A-Z0-9_]{0,15}\z/.match?(name)
      raise "duplicate module #{name}" if @modules.key?(name)
      split=w[3..].index('OUT')+3; ins=w[3...split]; outs=w[(split+1)..]; seen=[]
      (ins+outs).each { |p| raise "bad name #{p}" unless name?(p); raise "duplicate port #{p}" if seen.include?(p); seen<<p }
      driven=ins.dup; used=[]; body=[]; reads=[]
      lines.drop(1).each_with_index do |line,i|
        line_no=header_no+i+1; a=line.split(' '); kind=a[0]; n=a[1]
        if TYPES.include?(kind)
          raise 'bad gate syntax' unless a.size>=5 && a[-3]=='->' && a.count('->')==1
          raise "bad name #{n}" unless name?(n)
          inputs=a[2...-3]; output=a[-2]; delay=a[-1]; low=%w[NOT BUF].include?(kind) ? 1 : kind=='MUX2' ? 3 : 2; high=TYPES.index(kind)<6 ? 8 : low
          raise "bad input count #{inputs.size} for #{kind}" unless (low..high).cover?(inputs.size)
          (inputs+[output]).each { |s| raise "bad name #{s}" unless name?(s) }
          raise "bad delay #{delay}" unless number?(delay) && delay.to_i<=1000
          raise "duplicate name #{n}" if used.include?(n)
          raise "multiple drivers for #{output}" if driven.include?(output)
          driven<<output; used<<n; body<<Gate.new(n,kind,inputs,output,delay.to_i); inputs.each { |s| reads<<[line_no,s] }
        elsif kind=='INST'
          raise 'bad instance syntax' if a.size<3
          raise "bad name #{n}" unless name?(n)
          m=lookup(a[2]); connections={}
          a.drop(3).each do |word|
            p=word.split('=',-1); raise "bad connection #{word}" unless p.size==2 && !p[0].empty? && !p[1].empty?
            port,s=p; raise "unknown port #{port}" unless (m.inputs+m.outputs).include?(port)
            raise "duplicate connection #{port}" if connections.key?(port)
            raise "bad name #{s}" unless name?(s)
            connections[port]=s
          end
          m.inputs.each { |p| raise "unconnected input #{p}" unless connections.key?(p) }
          raise "duplicate name #{n}" if used.include?(n)
          connections.each { |p,s| next unless m.outputs.include?(p); raise "multiple drivers for #{s}" if driven.include?(s); driven<<s }
          used<<n; body<<Instance.new(n,m,connections); connections.each { |p,s| reads<<[line_no,s] if m.inputs.include?(p) }
        else raise "unknown statement #{kind}"
        end
      end
      outs.each { |s| reads<<[header_no,s] }
      reads.each { |n,s| next if driven.include?(s); line_no=n; raise "undriven signal #{s}" }
      @modules[name]=Mod.new(name,ins,outs,body); gates=body.count { |x| x.is_a?(Gate) }
      puts "defined #{name} inputs #{ins.size} outputs #{outs.size} gates #{gates} instances #{body.size-gates}"
    rescue RuntimeError=>e
      puts "error: line #{line_no}: #{e.message}"
    end
  end
  def hierarchy(m,depth)
    m.body.each { |x| next unless x.is_a?(Instance); puts '  '*depth+"#{x.name} #{x.mod.name}"; hierarchy(x.mod,depth+1) }
  end
  def execute(line_no,w)
    cmd=w[0]; a=w.drop(1)
    raise "unknown command #{cmd}" unless COUNTS.key?(cmd)
    raise 'wrong argument count' unless a.size>=COUNTS[cmd] && (%w[WATCH UNWATCH SHOW].include?(cmd)||a.size==COUNTS[cmd])
    raise 'no circuit' if SIM.include?(cmd) && !@sim
    s=@sim
    raise 'simulation halted' if %w[SET APPLY PULSE CLOCK RUN].include?(cmd) && s.halted
    case cmd
    when 'MODULES'
      puts "modules #{@modules.size}"
      @modules.each_value { |m| puts "#{m.name} inputs #{m.inputs.size} outputs #{m.outputs.size} gates #{Circuit.new(m).gates.size}" }
    when 'BUILD','NETLIST','HIERARCHY','STATS','TRUTHTABLE','EQUIV','FAULTS','CRITICAL','PERIOD'
      m=lookup(a[0]); m2=lookup(a[1]) if cmd=='EQUIV'; c=Circuit.new(m)
      case cmd
      when 'BUILD'
        @sim=Simulation.new(c); puts "built #{c.name} signals #{c.signals.size} gates #{c.gates.size}"
      when 'NETLIST'
        puts "netlist #{c.name} gates #{c.gates.size} signals #{c.signals.size}"
        c.gates.each { |g| puts "#{g.name} #{g.kind} #{g.inputs.join(' ')} -> #{g.output} #{g.delay}" }
      when 'HIERARCHY' then puts m.name; hierarchy(m,1)
      when 'STATS'
        levels=(c.inputs+c.flops.map(&:output)).to_h { |x| [x,0] }
        c.order&.each { |g| levels[g.output]=g.inputs.map { |x| levels[x] }.max+1 }
        puts "stats #{c.name} gates #{c.gates.size} signals #{c.signals.size} depth #{c.order ? levels.values.max : '-'}"
        puts (['types']+TYPES.flat_map { |t| n=c.gates.count { |g| g.kind==t }; n==0 ? [] : [t,n] }).join(' ')
        best=c.signals.max_by { |x| c.readers[x].size }; puts "max fanout #{best} #{c.readers[best].size}"
      when 'CRITICAL','PERIOD'
        period=cmd=='PERIOD'; raise "#{c.name} has no flip-flops" if period && c.flops.empty?
        raise "#{c.name} has a combinational loop" unless c.order
        late,early,prev=c.arrivals(period); ends=period ? c.flops.map { |g| g.inputs[1] } : c.outputs
        ends.each { |x| puts(late.key?(x) ? "#{x} min #{early[x]} max #{late[x]}" : "#{x} unreachable") } unless period
        reached=ends.select { |x| late.key?(x) }; heading=period ? "flip-flops #{c.flops.size} period" : 'critical'
        if reached.empty? then puts heading+' none'
        else
          best=reached.max_by { |x| late[x] }; path=[best]; path<<prev[path[-1]] while prev.key?(path[-1]); puts "#{heading} #{late[best]}: #{path.reverse.join(' -> ')}"
        end
      else
        c.combinational; rows=(0...2**c.inputs.size).map { |r| bits(r,c.inputs.size) }; expected=rows.map { |b| c.evaluate(b) }
        if cmd=='TRUTHTABLE'
          puts (c.inputs+['|']+c.outputs).join(' '); rows.each_with_index { |b,r| puts (b.chars+['|']+expected[r].chars).join(' ') }
        elsif cmd=='EQUIV'
          d=Circuit.new(m2).combinational; raise 'port mismatch' unless c.inputs.size==d.inputs.size && c.outputs.size==d.outputs.size
          r=rows.each_index.find { |i| expected[i]!=d.evaluate(rows[i]) }; puts(r ? "not equivalent at #{rows[r]}: #{expected[r]} vs #{d.evaluate(rows[r])}" : 'equivalent')
        else
          undetected=[]; tests=[]
          c.signals.each { |x| %w[0 1].each { |v| r=rows.each_index.find { |i| c.evaluate(rows[i],x,v)!=expected[i] }; r ? tests<<r : undetected<<"#{x}/#{v}" } }
          total=2*c.signals.size; puts "faults #{total} detected #{total-undetected.size}"; undetected.each { |f| puts 'undetected '+f }; puts (['tests']+tests.uniq.sort.map { |r| rows[r] }).join(' ')
        end
      end
    when 'RESET' then s.reset; puts 'reset'
    when 'SET'
      t=time(a[0]); input(a[1]); value(a[2]); s.schedule(t,a[1],a[2]); puts "set #{a[1]} #{a[2]} at #{t}"
    when 'APPLY'
      t=time(a[0]); b=a[1]; raise "bad vector #{b}" unless b.size==s.circuit.inputs.size && /\A[01X]*\z/.match?(b)
      s.circuit.inputs.each_with_index { |x,i| s.schedule(t,x,b[i]) }; puts "apply #{b} at #{t}"
    when 'PULSE','CLOCK'
      input(a[0]); t=time(a[1]); width=number(a[2],true)
      if cmd=='PULSE' then s.schedule(t,a[0],'1'); s.schedule(t+width,a[0],'0'); puts "pulse #{a[0]} #{t} #{t+width}"
      else count=number(a[3],true); count.times { |i| s.schedule(t+i*width,a[0],(i%2).to_s) }; puts "clock #{a[0]} events #{count} last #{t+(count-1)*width}" end
    when 'RUN'
      t=number(a[0]); raise "time #{t} is not after #{s.time}" if t<=s.time; s.run(t)
    when 'WATCH','UNWATCH'
      seen=[]; a.each { |x| signal(x); bad=cmd=='WATCH' ? s.watch.include?(x)||seen.include?(x) : !s.watch.include?(x)||seen.include?(x); raise "#{cmd=='WATCH' ? 'already watched' : 'not watched'} #{x}" if bad; seen<<x }
      s.watch=cmd=='WATCH' ? s.watch+a : s.watch-a; puts 'watching '+(s.watch.empty? ? 'nothing' : s.watch.join(' '))
    when 'SHOW'
      a.each { |x| signal(x) }; puts (a.empty? ? s.describe(s.circuit.inputs)+['|']+s.describe(s.circuit.outputs) : s.describe(a)).join(' ')
    when 'CHECK'
      signal(a[0]); value(a[1]); puts "check #{a[0]}=#{a[1]} "+(s.values[a[0]]==a[1] ? 'ok' : "failed (#{s.values[a[0]]})")
    when 'PROBE'
      x=a[0]; signal(x); g=s.circuit.driver[x]; puts "#{x}=#{s.values[x]} driven by "+(g ? "#{g.name} #{g.kind} #{s.describe(g.inputs).join(' ')} delay #{g.delay}" : 'input')
      r=s.circuit.readers[x]; puts (['fanout',r.size]+r.map(&:name)).join(' ')
    when 'WAVE'
      first=number(a[0]); last=number(a[1]); raise "bad range #{first} #{last}" unless first<last && last<=s.time
      raise 'nothing watched' if s.watch.empty?
      s.watch.each do |x|
        h=s.history[x]; i=0; v='X'; wave=(first...last).map { |t| while i<h.size && h[i][0]<=t; v=h[i][1]; i+=1 end; v }.join; puts x+' '+wave
      end
    when 'HISTORY'
      x=a[0]; signal(x); h=s.history[x]; puts (['history',x,'changes',h.size]+h.map { |t,v| "#{t}:#{v}" }).join(' ')
    when 'ACTIVITY'
      k=number(a[0],true); s.circuit.signals.sort_by { |x| [-s.history[x].size,x] }.first(k).each { |x| puts "#{x} #{s.history[x].size}" }
    when 'STATUS'
      puts "circuit #{s.circuit.name} time #{s.time} pending #{s.queue.size} events #{s.processed} halted #{s.halted ? 'yes' : 'no'}"
      puts "values 0:#{s.values.values.count('0')} 1:#{s.values.values.count('1')} X:#{s.values.values.count('X')}"
    end
  rescue RuntimeError=>e
    puts "error: line #{line_no}: #{e.message}"
  end
end
lines=STDIN.each_line.map(&:chomp); simulator=Simulator.new; i=0
while i<lines.size && lines[i]!='END'
  if lines[i].split(' ')[0]=='MODULE'
    last=i+1; last+=1 until lines[last]=='ENDMODULE'; simulator.define(i+1,lines[i...last]); i=last+1
  else simulator.execute(i+1,lines[i].split(' ')); i+=1 end
end
