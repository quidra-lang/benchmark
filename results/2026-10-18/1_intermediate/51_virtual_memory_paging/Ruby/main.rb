POLICIES = %w[FIFO LRU LFU NRU AGING CLOCK ECLOCK WSCLOCK RANDOM OPT].freeze
DEFAULTS = { 'page'=>256, 'frames'=>4, 'tlb'=>4, 'sets'=>1, 'policy'=>'FIFO',
             'scope'=>'GLOBAL', 'asid'=>'OFF', 'tick'=>0, 'tau'=>8, 'seed'=>1 }.freeze

def ratio(x, y)
  v = y.zero? ? 0 : 10_000 * x / y
  format('%d.%02d%%', v / 100, v % 100)
end

def address(n) = '0x' + n.to_s(16).upcase

class Simulation
  attr_reader :config, :processes, :time, :faults, :writebacks, :tlbhits, :events
  def initialize(config, references)
    @config, @references = config, references
    @processes, @events, @history, @swap = {}, [], [], {}
    @frames = Array.new(config['frames'])
    @tlb = Array.new(config['sets']) { [] }
    @time = @faults = @writebacks = @tlbhits = @zero = @swapin = @switches = 0
    @cursor = @hand = 0
    @random = config['seed']
    @fixed = @trace = false
    @previous = nil
  end
  def declare(pid, count)
    raise 'processes are fixed' if @fixed
    raise "duplicate process #{pid}" if @processes.key?(pid)
    raise 'invalid page count' unless (1..256).cover?(count)
    if @processes.length >= 8 || (@config['scope'] == 'LOCAL' && @processes.length >= @frames.length)
      raise 'too many processes'
    end
    pages = Array.new(count) do |i|
      { pid: pid, p: i, frame: nil, slot: nil, ro: false, locked: false, r: 0, m: 0,
        load: 0, last: 0, uses: 0, age: 0, ever: false }
    end
    @processes[pid] = { pages: pages, accesses: 0, faults: 0, writebacks: 0,
                        segfaults: 0, protfaults: 0, peak: 0, exited: false, hand: 0, refs: [] }
  end
  def process(pid)
    p = @processes[pid]
    raise "unknown process #{pid}" unless p
    raise "process #{pid} exited" if p[:exited]
    p
  end
  def resident(pid) = @frames.count { |p| p && p[:pid] == pid }
  def quota(pid)
    ids = @processes.keys.sort
    q, r = @frames.length.divmod(ids.length)
    q + (ids.index(pid) < r ? 1 : 0)
  end
  def invalidate(page)
    @tlb.each { |set| set.reject! { |p| p.equal?(page) } }
  end
  def writeback(page)
    @writebacks += 1
    @processes[page[:pid]][:writebacks] += 1
    page[:m] = 0
    unless page[:slot]
      slot = 0
      slot += 1 while @swap.key?(slot)
      page[:slot] = slot
      @swap[slot] = page
    end
  end
  def victim(pid)
    candidates = @frames.each_index.select do |i|
      @frames[i] && (@config['scope'] == 'GLOBAL' || @frames[i][:pid] == pid)
    end
    unlocked = candidates.reject { |i| @frames[i][:locked] }
    candidates = unlocked unless unlocked.empty?
    policy = @config['policy']
    if policy == 'RANDOM'
      @random = 48_271 * @random % 2_147_483_647
      return candidates[@random % candidates.length]
    end
    if policy == 'OPT'
      return candidates.max_by do |i|
        page = @frames[i]
        next_use = (@cursor...@references.length).find do |j|
          ref = @references[j]
          ref[0] == page[:pid] && ref[2] / @config['page'] == page[:p]
        end
        [next_use || Float::INFINITY, -i]
      end
    end
    keys = { 'FIFO'=>:load, 'LRU'=>:last, 'LFU'=>:uses, 'AGING'=>:age }
    if keys.key?(policy)
      return candidates.min_by do |i|
        page = @frames[i]
        [page[keys[policy]], page[:load]]
      end
    end
    return candidates.min_by { |i| [2 * @frames[i][:r] + @frames[i][:m], i] } if policy == 'NRU'
    hand = @config['scope'] == 'GLOBAL' ? @hand : @processes[pid][:hand]
    circular = candidates.sort_by { |i| (i - hand) % @frames.length }
    chosen = nil
    case policy
    when 'CLOCK'
      until chosen
        circular.each do |i|
          if @frames[i][:r].zero?
            chosen = i
            break
          end
          @frames[i][:r] = 0
        end
      end
    when 'ECLOCK'
      until chosen
        chosen = circular.find { |i| @frames[i][:r].zero? && @frames[i][:m].zero? }
        break if chosen
        circular.each do |i|
          if @frames[i][:r].zero? && @frames[i][:m] == 1
            chosen = i
            break
          end
          @frames[i][:r] = 0
        end
      end
    when 'WSCLOCK'
      circular.each do |i|
        page = @frames[i]
        if page[:r] == 1
          page[:r], page[:last] = 0, @time
        elsif @time - page[:last] > @config['tau']
          if page[:m].zero?
            chosen = i
            break
          end
          writeback(page)
        end
      end
      chosen ||= circular.find { |i| @frames[i][:m].zero? } || circular.first
    end
    if @config['scope'] == 'GLOBAL'
      @hand = (chosen + 1) % @frames.length
    else
      @processes[pid][:hand] = (chosen + 1) % @frames.length
    end
    chosen
  end
  def access(pid, op, addr, silent = false)
    @fixed = true
    @cursor += 1
    proc = process(pid)
    if addr >= proc[:pages].length * @config['page']
      proc[:segfaults] += 1
      puts "SEGFAULT P#{pid} #{address(addr)}" unless silent
      return
    end
    page = proc[:pages][addr / @config['page']]
    if op == 'W' && page[:ro]
      proc[:protfaults] += 1
      puts "PROTFAULT P#{pid} #{address(addr)}" unless silent
      return
    end
    @events << [:access, pid, op, addr]
    @time += 1
    proc[:accesses] += 1
    proc[:refs] << page[:p]
    switched = !@previous.nil? && @previous != pid
    if switched
      @switches += 1
      @tlb.each(&:clear) if @config['asid'] == 'OFF'
    end
    @previous = pid
    set = @tlb[page[:p] % @config['sets']]
    fault = false
    victim_page = nil
    wrote = false
    if set.include?(page)
      result = 'TLBHIT'
      @tlbhits += 1
      set.delete(page)
    else
      if page[:frame]
        result = 'HIT'
      else
        fault = true
        @faults += 1
        proc[:faults] += 1
        if page[:slot]
          @swapin += 1
          result = 'FAULT SWAPIN'
        else
          @zero += 1
          result = 'FAULT ZERO'
        end
        free = @frames.index(nil)
        use_free = @config['scope'] == 'GLOBAL' ? !free.nil? : resident(pid) < quota(pid)
        frame = use_free ? free : victim(pid)
        victim_page = @frames[frame]
        if victim_page
          invalidate(victim_page)
          wrote = victim_page[:m] == 1
          writeback(victim_page) if wrote
          victim_page[:frame] = nil
        end
        @frames[frame] = page
        page[:frame], page[:load], page[:uses], page[:m], page[:age] = frame, @time, 0, 0, 0
        proc[:peak] = [proc[:peak], resident(pid)].max
      end
      set.shift if set.length == @config['tlb'] / @config['sets']
    end
    set << page
    page[:r] = 1
    page[:m] = 1 if op == 'W'
    page[:last] = @time
    page[:uses] += 1
    page[:ever] = true
    @history << fault
    tick = @config['tick'].positive? && @time % @config['tick'] == 0
    if tick
      @frames.compact.each do |p|
        p[:age] = p[:age] / 2 + 128 * p[:r]
        p[:r] = 0
      end
    end
    return unless @trace && !silent
    text = "t=#{@time} P#{pid} #{op} #{address(addr)} page=#{page[:p]} frame=#{page[:frame]} phys=#{address(page[:frame] * @config['page'] + addr % @config['page'])} #{result}"
    text += " evict=P#{victim_page[:pid]}:#{victim_page[:p]}" if victim_page
    text += ' writeback' if wrote
    text += ' switch' if switched
    puts text
    puts "t=#{@time} tick" if tick
  end
  def exit_process(pid, silent = false)
    proc = process(pid)
    freed, slots = resident(pid), 0
    proc[:pages].each do |page|
      @frames[page[:frame]] = nil if page[:frame]
      page[:frame] = nil
      invalidate(page)
      unless page[:slot].nil?
        @swap.delete(page[:slot])
        page[:slot] = nil
        slots += 1
      end
    end
    proc[:exited] = true
    @events << [:exit, pid]
    puts "EXIT P#{pid} freed=#{freed} slots=#{slots}" unless silent
  end
  def attributes(cmd, pid, first, last, protection = nil)
    proc = process(pid)
    raise 'invalid page range' if first > last || last >= proc[:pages].length
    (first..last).each do |i|
      page = proc[:pages][i]
      if cmd == 'PROTECT'
        page[:ro] = protection == 'RO'
      else
        page[:locked] = cmd == 'LOCK'
      end
    end
    @events << [:attribute, cmd, pid, first, last] unless cmd == 'PROTECT'
  end
  def clean(silent = false)
    pages = @frames.compact.select { |p| p[:m] == 1 }
    pages.each { |p| writeback(p) }
    @events << [:clean]
    puts "CLEAN written=#{pages.length}" unless silent
  end
  def rerun(policy, frames)
    config = @config.merge('policy'=>policy, 'frames'=>frames)
    refs = @events.select { |e| e[0] == :access }.map { |e| e[1..] }
    sim = Simulation.new(config, refs)
    @processes.each { |pid,p| sim.declare(pid, p[:pages].length) }
    @events.each do |e|
      case e[0]
      when :access then sim.access(*e[1..], true)
      when :exit then sim.exit_process(e[1], true)
      when :clean then sim.clean(true)
      when :attribute then sim.attributes(*e[1..])
      end
    end
    sim
  end
  def command(words)
    cmd = words[0]
    pid = words[1].to_i
    case cmd
    when 'PROCESS' then declare(pid, words[2].to_i)
    when 'EXIT' then exit_process(pid)
    when 'PROTECT', 'LOCK', 'UNLOCK' then attributes(cmd, pid, words[2].to_i, words[3].to_i, words[4])
    when 'TRACE' then @trace = words[1] == 'ON'
    when 'CLEAN' then clean
    when 'SUMMARY'
      puts "SUMMARY policy=#{@config['policy']} scope=#{@config['scope']} time=#{@time}"
      seg = @processes.values.sum { |p| p[:segfaults] }
      prot = @processes.values.sum { |p| p[:protfaults] }
      puts "total faults=#{@faults} zero=#{@zero} swapin=#{@swapin} faultrate=#{ratio(@faults,@time)} tlbhits=#{@tlbhits} tlbrate=#{ratio(@tlbhits,@time)} writebacks=#{@writebacks} switches=#{@switches} segfaults=#{seg} protfaults=#{prot}"
      @processes.keys.sort.each do |id|
        p = @processes[id]
        line = "P#{id} accesses=#{p[:accesses]} faults=#{p[:faults]} writebacks=#{p[:writebacks]} segfaults=#{p[:segfaults]} protfaults=#{p[:protfaults]} resident=#{resident(id)} peak=#{p[:peak]}"
        line += " quota=#{quota(id)}" if @config['scope'] == 'LOCAL'
        line += ' exited' if p[:exited]
        puts line
      end
    when 'FRAMES'
      puts "FRAMES used=#{@frames.compact.length}/#{@frames.length}"
      @frames.each_with_index do |p,i|
        if p
          line = "#{i} P#{p[:pid]}:#{p[:p]} R=#{p[:r]} M=#{p[:m]} load=#{p[:load]} last=#{p[:last]} uses=#{p[:uses]} age=#{p[:age]}"
          puts line + (p[:locked] ? ' locked' : '')
        else
          puts "#{i} free"
        end
      end
      if %w[CLOCK ECLOCK WSCLOCK].include?(@config['policy'])
        puts(@config['scope'] == 'GLOBAL' ? "hand=#{@hand}" : 'hand' + @processes.keys.sort.map { |id| " P#{id}=#{@processes[id][:hand]}" }.join)
      end
    when 'PAGETABLE'
      p = process(pid)
      puts "PAGETABLE P#{pid} pages=#{p[:pages].length} resident=#{resident(pid)}"
      p[:pages].select { |pg| pg[:ever] }.each do |pg|
        state = if pg[:frame]
                  "frame=#{pg[:frame]} R=#{pg[:r]} M=#{pg[:m]}"
                elsif pg[:slot]
                  "swap=#{pg[:slot]}"
                else 'zero' end
        puts "#{pg[:p]} #{state}" + (pg[:ro] ? ' RO' : '') + (pg[:locked] ? ' locked' : '')
      end
    when 'TLB'
      puts "TLB used=#{@tlb.sum(&:length)}/#{@config['tlb']} sets=#{@config['sets']}"
      @tlb.each_with_index { |set,i| puts "set #{i}:" + set.reverse.map { |p| " P#{p[:pid]}:#{p[:p]}->#{p[:frame]}" }.join }
    when 'SWAP'
      puts "SWAP used=#{@swap.length}"
      @swap.keys.sort.each { |slot| p=@swap[slot]; puts "#{slot} P#{p[:pid]}:#{p[:p]}" }
    when 'COMPARE'
      puts "COMPARE accesses=#{@time} frames=#{@frames.length}"
      results = POLICIES.each_with_index.map do |policy,i|
        sim = rerun(policy, @frames.length)
        puts "#{policy} faults=#{sim.faults} writebacks=#{sim.writebacks} tlbhits=#{sim.tlbhits}"
        [sim.faults, sim.writebacks, i, policy]
      end
      puts 'ranking ' + results.sort.map(&:last).join(' ')
    when 'CURVE'
      policy, lo, hi = words[1], words[2].to_i, words[3].to_i
      raise 'unknown policy' unless POLICIES.include?(policy)
      if lo < 1 || lo > hi || hi > 16 || (@config['scope'] == 'LOCAL' && lo < @processes.length)
        raise 'invalid frame range'
      end
      puts "CURVE #{policy} frames=#{lo}..#{hi}"
      previous = nil
      (lo..hi).each do |f|
        faults = rerun(policy, f).faults
        puts "F=#{f} faults=#{faults}" + (previous && faults > previous ? ' ANOMALY' : '')
        previous = faults
      end
    when 'EAT'
      if @time.zero?
        puts 'EAT accesses=0'
      else
        a,b,c = words[1..].map(&:to_i)
        total = a*@time+b*(2*@time-@tlbhits)+c*(@swapin+@writebacks)
        v = 100*total/@time
        puts "EAT accesses=#{@time} total=#{total} average=#{format('%d.%02d',v/100,v%100)}"
      end
    when 'TIMELINE'
      w = pid
      raise 'invalid window' if w < 1
      puts "TIMELINE window=#{w}" + @history.each_slice(w).map { |slice| " #{slice.count(true)}" }.join
    when 'WSET'
      p = process(pid)
      w = words[2].to_i
      raise 'invalid window' if w < 1
      pages = p[:refs].last(w).uniq.sort
      puts "WSET P#{pid} window=#{w} size=#{pages.length}" + pages.map { |i| " #{i}" }.join
    when 'HOT'
      p = process(pid)
      k = words[2].to_i
      raise 'invalid count' if k < 1
      pages = p[:refs].tally.sort_by { |page,count| [-count,page] }.first(k)
      puts "HOT P#{pid}" + pages.map { |page,count| " #{page}:#{count}" }.join
    else
      access(words[0].to_i, words[1], words[2].to_i(16))
    end
  end
end

def system_settings(words)
  config = DEFAULTS.dup
  seen = {}
  words.drop(1).each do |pair|
    key,value = pair.split('=')
    raise "unknown key #{key}" unless config.key?(key)
    raise "duplicate key #{key}" if seen[key]
    seen[key] = true
    valid = case key
            when 'policy' then POLICIES.include?(value)
            when 'scope' then %w[GLOBAL LOCAL].include?(value)
            when 'asid' then %w[ON OFF].include?(value)
            else
              n = value.to_i
              ranges = { 'frames'=>1..16, 'tlb'=>1..8, 'sets'=>1..8, 'tick'=>0..1000,
                         'tau'=>1..1000, 'seed'=>1..2_147_483_646 }
              key == 'page' ? n >= 16 && n <= 4096 && (n & (n-1)).zero? : ranges[key].cover?(n)
            end
    raise "invalid #{key}" unless valid
    config[key] = %w[policy scope asid].include?(key) ? value : value.to_i
  end
  raise 'invalid sets' unless (config['tlb'] % config['sets']).zero?
  config
end

commands = []
STDIN.gets.to_i.times do
  w = STDIN.gets.split
  case w[0]
  when 'LOOP'
    pid,op,start,step,n,repeats = w[1].to_i,w[2],w[3].to_i(16),w[4].to_i,w[5].to_i,w[6].to_i
    repeats.times { n.times { |i| commands << [pid.to_s,op,address(start+i*step)] } }
  when 'RAND'
    pid,lo,hi,count,x,rate = w[1].to_i,w[2].to_i(16),w[3].to_i(16),w[4].to_i,w[5].to_i,w[6].to_i
    count.times do
      x = 48_271*x % 2_147_483_647
      addr = lo+x%(hi-lo)
      x = 48_271*x % 2_147_483_647
      commands << [pid.to_s,x%100 < rate ? 'W' : 'R',address(addr)]
    end
  else commands << w
  end
end
simulation = nil
commands.each_with_index do |words,i|
  begin
    if words[0] == 'SYSTEM'
      simulation = nil
      config = system_settings(words)
      rest = commands[(i+1)..].take_while { |w| w[0] != 'SYSTEM' }
      refs = rest.select { |w| w[0].match?(/\A\d/) }.map { |w| [w[0].to_i,w[1],w[2].to_i(16)] }
      simulation = Simulation.new(config,refs)
      puts 'SYSTEM ' + config.map { |key,value| "#{key}=#{value}" }.join(' ')
    elsif simulation
      simulation.command(words)
    else
      puts 'ERROR no system'
    end
  rescue RuntimeError => error
    puts "ERROR #{error.message}"
  end
end
