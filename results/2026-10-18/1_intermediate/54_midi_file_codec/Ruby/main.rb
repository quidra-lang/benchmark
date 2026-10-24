CHANNELS = %w[NOTE_OFF NOTE_ON POLY_PRESSURE CONTROL PROGRAM CHANNEL_PRESSURE PITCH_BEND].freeze
TEXTS = %w[TEXT_EVENT COPYRIGHT TRACK_NAME INSTRUMENT_NAME LYRIC MARKER CUE_POINT].freeze
METAS = {0=>'SEQUENCE_NUMBER',32=>'CHANNEL_PREFIX',47=>'END_OF_TRACK',81=>'TEMPO',84=>'SMPTE_OFFSET',88=>'TIME_SIGNATURE',89=>'KEY_SIGNATURE',127=>'SEQUENCER_SPECIFIC'}.merge(TEXTS.each_with_index.to_h { |s,i| [i+1,s] }).freeze
MAJOR = %w[Cb Gb Db Ab Eb Bb F C G D A E B F# C#].freeze
MINOR = %w[Ab Eb Bb F C G D A E B F# C# G# D# A#].freeze
NOTES = (0..127).map { |p| %w[C C# D D# E F F# G G# A A# B][p%12] + (p/12-1).to_s }.freeze

def integer(bytes)
  bytes.reduce(0) { |v,b| v*256+b }
end

def big(value, count)
  Array.new(count) { |i| (value >> (8*(count-1-i))) & 255 }
end

def vlq(value)
  bytes = [value & 127]
  while (value >>= 7) > 0
    bytes.unshift((value & 127) | 128)
  end
  bytes
end

def event_type(e)
  return CHANNELS[(e[:s] >> 4)-8] if e[:s] < 240
  return e[:s] == 240 ? 'SYSEX' : 'SYSEX_ESCAPE' if e[:s] != 255
  METAS[e[:m]] || 'META'
end

def event_fields(e)
  d, s = e[:d], e[:s]
  if s < 240
    ch, kind = (s&15)+1, s>>4
    return [ch, NOTES[d[0]], d[1]] if [8,9,10].include?(kind)
    return [ch, d[0]+128*d[1]-8192] if kind == 14
    return [ch] + d
  end
  if s != 255 || e[:m] == 127 || !METAS.key?(e[:m])
    prefix = s == 255 && !METAS.key?(e[:m]) ? [format('%02X',e[:m])] : []
    return prefix + [d.size] + (d.empty? ? [] : [d.pack('C*').unpack1('H*').upcase])
  end
  case e[:m]
  when 0,81 then [integer(d)]
  when 1..7 then ['"' + d.pack('C*') + '"']
  when 32 then [d[0]+1]
  when 47 then []
  when 84 then d
  when 88 then ["#{d[0]}/#{1<<d[1]}",d[2],d[3]]
  when 89
    sf = d[0] >= 128 ? d[0]-256 : d[0]
    [(d[1] == 0 ? MAJOR : MINOR)[sf+7], d[1] == 0 ? 'major' : 'minor']
  end
end

def event_line(e, track)
  ([e[:t],track,event_type(e)] + event_fields(e)).join(' ')
end

def ordered(song)
  song[:tracks].each_with_index.flat_map { |tr,i| tr.each_with_index.map { |e,j| [e,i,j] } }.sort_by { |e,i,j| [e[:t],i,j] }
end

def length(song)
  song[:tracks].map { |tr| tr[-1][:t] }.max
end

def summary(song)
  "format #{song[:f]} tracks #{song[:tracks].size} division #{song[:div]} events #{song[:tracks].sum(&:size)}"
end

class Reader
  def initialize(bytes)
    @bytes, @p, @limit, @start = bytes, 0, bytes.size, 0
  end
  def fail_at(reason, position)
    raise "byte #{position}: #{reason}"
  end
  def read
    fail_at('truncated event',@start) if @p >= @limit
    b = @bytes[@p]
    @p += 1
    b
  end
  def variable
    start, value = @p, 0
    4.times do
      b = read
      value = value*128+(b&127)
      return value if b < 128
    end
    fail_at('variable-length value too long',start)
  end
  def chunk(id)
    p = @p
    fail_at('truncated chunk',p) if @bytes.size-p < 8
    fail_at('bad chunk id',p) unless @bytes[p,4].pack('C*') == id
    size = integer(@bytes[p+4,4])
    fail_at('truncated chunk',p) if p+8+size > @bytes.size
    @p = p+8
    size
  end
  def parse
    size = chunk('MThd')
    fail_at('bad header length',4) unless size == 6
    f, count, division = [8,10,12].map { |i| integer(@bytes[i,2]) }
    fail_at('bad format',8) if f > 2
    fail_at('bad track count',10) if count == 0 || (f == 0 && count != 1)
    fail_at('smpte timing not supported',12) if division >= 32768
    fail_at('bad division',12) if division == 0
    @p = 14
    tracks = []
    count.times do
      fail_at('missing track',@bytes.size) if @p == @bytes.size
      size = chunk('MTrk')
      @limit = @p+size
      track, tick, running, ended = [], 0, nil, false
      while @p < @limit
        fail_at('event after end of track',@p) if ended
        @start = @p
        tick += variable
        fail_at('truncated event',@start) if @p >= @limit
        status_position = @p
        s = @bytes[@p]
        if s < 128
          fail_at('data byte without running status',@p) unless running
          s = running
        else
          @p += 1
        end
        e = {t:tick,s:s,d:[]}
        if s < 240
          running = s
          ((s>>4) == 12 || (s>>4) == 13 ? 1 : 2).times do
            pos = @p
            b = read
            fail_at('bad data byte',pos) if b >= 128
            e[:d] << b
          end
        elsif [240,247,255].include?(s)
          running = nil
          e[:m] = read if s == 255
          n = variable
          fail_at('truncated event',@start) if @p+n > @limit
          e[:d] = @bytes[@p,n]
          @p += n
          if s == 255
            fixed = {0=>2,32=>1,47=>0,81=>3,84=>5,88=>4,89=>2}
            fail_at('bad meta length',status_position) if fixed.key?(e[:m]) && n != fixed[e[:m]]
            d = e[:d]
            bad = case e[:m]
                  when 32 then d[0] > 15
                  when 81 then integer(d) == 0
                  when 88 then d[0] == 0 || d[1] > 6
                  when 89 then !(0..7).include?(d[0]) && !(249..255).include?(d[0]) || d[1] > 1
                  else false
                  end
            fail_at('bad meta data',status_position) if bad
            ended = e[:m] == 47
          end
        else
          fail_at('unknown status byte',status_position)
        end
        track << e
      end
      fail_at('missing end of track',@limit) unless ended
      tracks << track
      @limit = @bytes.size
    end
    fail_at('extra data',@p) if @p < @bytes.size
    {f:f,div:division,tracks:tracks}
  end
end

def valid_range(s, low, high)
  s && s.match?(/\A-?\d+\z/) && s.to_i.between?(low,high)
end

def text_event(line)
  tick, track, type, rest = line.split(' ',4)
  known = CHANNELS + METAS.values + %w[SYSEX SYSEX_ESCAPE META]
  raise 'unknown event type' unless known.include?(type)
  fields = TEXTS.include?(type) ? [rest] : (rest || '').split
  e = {t:tick.to_i,s:255,d:[]}
  e[:m] = METAS.key(type) if METAS.value?(type)
  good = true
  if CHANNELS.include?(type)
    kind = CHANNELS.index(type)+8
    count = [12,13,14].include?(kind) ? 2 : 3
    good = fields.size == count && valid_range(fields[0],1,16)
    if [8,9,10].include?(kind)
      note = NOTES.index(fields[1])
      good &&= !note.nil? && valid_range(fields[2],0,127)
      e[:d] = [note,fields[2].to_i]
    elsif kind == 14
      good &&= valid_range(fields[1],-8192,8191)
      value = fields[1].to_i+8192
      e[:d] = [value%128,value/128]
    else
      good &&= fields.drop(1).all? { |x| valid_range(x,0,127) }
      e[:d] = fields.drop(1).map(&:to_i)
    end
    e[:s] = kind*16+fields[0].to_i-1
  elsif TEXTS.include?(type)
    good = rest && rest.size >= 2 && rest.start_with?('"') && rest.end_with?('"') && !rest[1...-1].include?('"')
    e[:d] = good ? rest[1...-1].bytes : []
  elsif %w[SYSEX SYSEX_ESCAPE SEQUENCER_SPECIFIC META].include?(type)
    if type == 'META'
      tt = fields.shift
      good = tt && tt.match?(/\A[0-9A-F]{2}\z/) && !METAS.key?(tt.to_i(16))
      e[:m] = tt.to_i(16) if tt
    elsif type == 'SYSEX' || type == 'SYSEX_ESCAPE'
      e[:s] = type == 'SYSEX' ? 240 : 247
    end
    good &&= valid_range(fields[0],0,1_000_000)
    n = fields[0].to_i
    good &&= fields.size == (n == 0 ? 1 : 2)
    good &&= fields[1] && fields[1].size == 2*n && fields[1].match?(/\A[0-9A-F]+\z/) if n > 0
    e[:d] = n > 0 && good ? [fields[1]].pack('H*').bytes : []
  else
    case type
    when 'SEQUENCE_NUMBER','TEMPO','CHANNEL_PREFIX'
      range = {'SEQUENCE_NUMBER'=>[0,65535],'TEMPO'=>[1,16777215],'CHANNEL_PREFIX'=>[1,16]}[type]
      good = fields.size == 1 && valid_range(fields[0],*range)
      v = fields[0].to_i
      e[:d] = type == 'CHANNEL_PREFIX' ? [v-1] : big(v,type == 'TEMPO' ? 3 : 2)
    when 'END_OF_TRACK' then good = fields.empty?
    when 'SMPTE_OFFSET'
      good = fields.size == 5 && fields.all? { |x| valid_range(x,0,255) }
      e[:d] = fields.map(&:to_i)
    when 'TIME_SIGNATURE'
      nn, dd = (fields[0] || '').split('/').map(&:to_i)
      good = fields.size == 3 && nn && nn.between?(1,255) && [1,2,4,8,16,32,64].include?(dd) && fields.drop(1).all? { |x| valid_range(x,0,255) }
      e[:d] = good ? [nn, [1,2,4,8,16,32,64].index(dd),fields[1].to_i,fields[2].to_i] : []
    when 'KEY_SIGNATURE'
      keys = fields[1] == 'major' ? MAJOR : MINOR
      index = keys.index(fields[0])
      good = fields.size == 2 && %w[major minor].include?(fields[1]) && index
      e[:d] = good ? [(index-7)%256,fields[1] == 'major' ? 0 : 1] : []
    end
  end
  raise 'bad value' unless good
  [e,track.to_i]
end

def parse_text(lines)
  header = lines[0].split
  unless header.size == 4 && header[0] == 'HEADER' && valid_range(header[1],0,2) && valid_range(header[2],1,65535) && valid_range(header[3],1,32767) && (header[1].to_i != 0 || header[2].to_i == 1)
    raise 'line 1: bad header'
  end
  f, count, division = header.drop(1).map(&:to_i)
  tracks, c = [[]], 0
  lines.drop(1).each_with_index do |line,i|
    begin
      e, tr = text_event(line)
      raise 'bad track' if tr >= count
      ended = !tracks[c].empty? && event_type(tracks[c][-1]) == 'END_OF_TRACK'
      raise 'out of order' if tr < c
      raise 'missing end of track' if tr > c && (!ended || tr > c+1)
      raise 'event after end of track' if tr == c && ended
      if tr == c+1
        c += 1
        tracks << []
      end
      raise 'out of order' if !tracks[c].empty? && e[:t] < tracks[c][-1][:t]
      tracks[c] << e
    rescue RuntimeError => ex
      raise "line #{i+2}: #{ex.message}"
    end
  end
  if c+1 < count || tracks[c].empty? || event_type(tracks[c][-1]) != 'END_OF_TRACK'
    raise "line #{lines.size+1}: missing end of track"
  end
  {f:f,div:division,tracks:tracks}
end

def pairing(song)
  queues, notes, unmatched = {}, [], []
  ordered(song).each_with_index do |(e,tr,_),order|
    kind = e[:s]>>4
    next unless kind == 8 || kind == 9
    key = [e[:s]&15,e[:d][0]]
    on = kind == 9 && e[:d][1] > 0
    item = [e,tr,order,on]
    queues[key] ||= []
    if on
      queues[key] << item
    elsif queues[key].empty?
      unmatched << item
    else
      first = queues[key].shift
      notes << {on:first[0],off:e,order:first[2],start:first[0][:t],length:e[:t]-first[0][:t],ch:key[0]+1,p:key[1],v:first[0][:d][1]}
    end
  end
  queues.each_value { |q| unmatched.concat(q) }
  notes.sort_by! { |n| [n[:start],n[:ch],n[:p],n[:order]] }
  [notes,unmatched.sort_by { |item| item[2] }]
end

def time_position(song, tick)
  sum, last, tempo, st, bar, nn, beat = 0,0,500000,0,1,4,song[:div]
  ordered(song).each do |e,_,_|
    break if e[:t] > tick
    if event_type(e) == 'TEMPO'
      sum += (e[:t]-last)*tempo
      last, tempo = e[:t], integer(e[:d])
    elsif event_type(e) == 'TIME_SIGNATURE'
      size = nn*beat
      bar += (e[:t]-st+size-1)/size
      st, nn, beat = e[:t],e[:d][0],[1,song[:div]*4/(1<<e[:d][1])].max
    end
  end
  micro = (sum+(tick-last)*tempo)/song[:div]
  x = tick-st
  ["#{micro/1000}.#{(micro%1000).to_s.rjust(3,'0')}","#{bar+x/(nn*beat)}:#{x%(nn*beat)/beat+1}:#{x%beat}"]
end

def encode(song, running, noteoff)
  bytes = 'MThd'.bytes + big(6,4) + big(song[:f],2) + big(song[:tracks].size,2) + big(song[:div],2)
  song[:tracks].each do |track|
    data, last, status = [],0,nil
    track.each do |e|
      data.concat(vlq(e[:t]-last))
      last = e[:t]
      s, d = e[:s], e[:d].dup
      if noteoff == 'ZERO' && s>>4 == 8
        s += 16
        d[1] = 0
      end
      if s < 240
        data << s unless running && status == s
        data.concat(d)
        status = s
      else
        status = nil
        data << s
        data << e[:m] if s == 255
        data.concat(vlq(d.size)).concat(d)
      end
    end
    bytes.concat('MTrk'.bytes).concat(big(data.size,4)).concat(data)
  end
  bytes.each_slice(16).with_index { |part,i| puts format('%04X: ',i*16) + part.map { |b| format('%02X',b) }.join(' ') }
  puts "#{bytes.size} bytes"
end

songs, running, noteoff = {},true,'KEEP'
known = %w[HEX TEXT DECODE ENCODE TIMING NOTES STATS ROLL TRANSPOSE QUANTIZE VELOCITY TEMPO FILTER MERGE SPLIT COPY LIST RUNNING NOTEOFF]
STDIN.gets.to_i.times do
  cmd, *args = STDIN.gets.chomp.split
  begin
    raise 'unknown command' unless known.include?(cmd)
    name = args[0]
    if %w[HEX TEXT].include?(cmd)
      lines = Array.new(args[1].to_i) { STDIN.gets.chomp }
      song = cmd == 'HEX' ? Reader.new(lines.join(' ').split.map { |s| s.to_i(16) }).parse : parse_text(lines)
      songs[name] = song
      puts "loaded #{name} #{summary(song)}"
      next
    end
    unless %w[LIST RUNNING NOTEOFF].include?(cmd)
      raise "no song #{name}" unless songs.key?(name)
    end
    song = songs[name]
    case cmd
    when 'LIST'
      puts 'no songs' if songs.empty?
      songs.keys.sort.each { |n| puts "#{n} #{summary(songs[n])}" }
    when 'RUNNING','NOTEOFF'
      raise 'bad argument' unless (cmd == 'RUNNING' ? %w[ON OFF] : %w[ZERO KEEP]).include?(name)
      if cmd == 'RUNNING'
        running = name == 'ON'
      else
        noteoff = name
      end
      puts "#{cmd.downcase} #{name.downcase}"
    when 'COPY'
      songs[args[1]] = Marshal.load(Marshal.dump(song))
      puts "copied #{name} to #{args[1]}"
    when 'DECODE'
      puts "HEADER #{song[:f]} #{song[:tracks].size} #{song[:div]}"
      song[:tracks].each_with_index { |tr,i| tr.each { |e| puts event_line(e,i) } }
    when 'ENCODE' then encode(song,running,noteoff)
    when 'TIMING'
      raise 'format 2 not supported' if song[:f] == 2
      ordered(song).each { |e,tr,_| puts "#{e[:t]} #{tr} #{event_type(e)} #{time_position(song,e[:t]).join(' ')}" }
      puts "end #{length(song)} #{time_position(song,length(song)).join(' ')}"
    when 'NOTES','STATS','ROLL'
      if cmd == 'ROLL'
        from, to, step = args.drop(1).map(&:to_i)
        raise 'bad argument' unless from.between?(0,10_000_000) && to.between?(1,10_000_000) && step.between?(1,10_000_000) && to > from && (to-from+step-1)/step <= 64
      elsif cmd == 'STATS' && song[:f] == 2
        raise 'format 2 not supported'
      end
      notes, unmatched = pairing(song)
      if cmd == 'NOTES'
        puts "notes #{notes.size} unmatched #{unmatched.size}"
        notes.each { |n| puts "#{n[:start]} #{n[:length]} #{n[:ch]} #{NOTES[n[:p]]} #{n[:v]}" }
        unmatched.each { |e,tr,_,on| puts "unmatched #{on ? 'on' : 'off'} #{e[:t]} #{tr} #{(e[:s]&15)+1} #{NOTES[e[:d][0]]}" }
      elsif cmd == 'ROLL'
        lines = []
        127.downto(0) do |p|
          chars = (0...((to-from+step-1)/step)).map do |i|
            a = from+i*step
            group = notes.select { |n| n[:p] == p }
            if group.any? { |n| a <= n[:start] && n[:start] < a+step } then '#'
            elsif group.any? { |n| n[:start] <= a && a < n[:start]+n[:length] } then '='
            else '.'
            end
          end.join
          lines << NOTES[p].ljust(4)+' '+chars if chars.match?(/[#=]/)
        end
        puts(lines.empty? ? ['empty'] : lines)
      else
        puts summary(song)
        puts "notes #{notes.size} unmatched #{unmatched.size}"
        notes.group_by { |n| n[:ch] }.sort.each do |ch, group|
          lo, hi = group.map { |n| n[:p] }.minmax
          puts "channel #{ch} notes #{group.size} range #{NOTES[lo]} #{NOTES[hi]}"
        end
        lo, hi = notes.map { |n| n[:p] }.minmax
        puts(notes.empty? ? 'range none' : "range #{NOTES[lo]} #{NOTES[hi]}")
        puts "length #{length(song)} ticks #{time_position(song,length(song))[0]} ms"
        changes = Hash.new(0)
        notes.each do |n|
          next if n[:length] == 0
          changes[n[:start]] += 1
          changes[n[:start]+n[:length]] -= 1
        end
        active, maximum, at = 0,0,0
        changes.sort.each { |t,delta| active += delta; maximum, at = active,t if active > maximum }
        puts(maximum == 0 ? 'polyphony 0' : "polyphony #{maximum} at #{at}")
      end
    when 'TRANSPOSE'
      amount = args[1].to_i
      channel = args[2]&.to_i
      raise 'bad argument' unless amount.between?(-127,127) && (!channel || channel.between?(1,16))
      kept, dropped = 0,[]
      song[:tracks].each_with_index do |tr,i|
        tr.reject! do |e|
          target = [8,9,10].include?(e[:s]>>4) && (!channel || (e[:s]&15)+1 == channel)
          next false unless target
          value = e[:d][0]+amount
          if value.between?(0,127)
            e[:d][0] = value
            kept += 1
            false
          else
            dropped << "dropped #{e[:t]} #{i} #{event_type(e)} #{(e[:s]&15)+1} #{NOTES[e[:d][0]]}"
            true
          end
        end
      end
      puts "transposed #{kept} dropped #{dropped.size}"
      puts dropped
    when 'QUANTIZE'
      grid, strength = args.drop(1).map(&:to_i)
      raise 'bad argument' unless grid.between?(1,1_000_000) && strength.between?(0,100)
      notes, unmatched = pairing(song)
      targets = notes.map { |n| [n[:on],n[:off]] } + unmatched.select { |x| x[3] }.map { |x| [x[0]] }
      moved = 0
      targets.each do |events|
        t = events[0][:t]
        lower = t/grid*grid
        g = t-lower <= lower+grid-t ? lower : lower+grid
        delta = (2*(g-t)*strength+100).div(200)
        moved += 1 unless delta == 0
        events.each { |e| e[:t] += delta }
      end
      song[:tracks].map! do |tr|
        ending = tr[-1]
        sorted = tr[0...-1].each_with_index.sort_by { |e,i| [e[:t],i] }.map(&:first)
        ending[:t] = [ending[:t],sorted.map { |e| e[:t] }.max || 0].max
        sorted + [ending]
      end
      puts "quantized #{targets.size} moved #{moved}"
    when 'VELOCITY'
      percent, offset = args.drop(1).map(&:to_i)
      raise 'bad argument' unless percent.between?(0,1000) && offset.between?(-127,127)
      count, clamped = 0,0
      ordered(song).each do |e,_,_|
        next unless e[:s]>>4 == 9 && e[:d][1] > 0
        count += 1
        v = (e[:d][1]*percent+50)/100+offset
        clamped += 1 unless v.between?(1,127)
        e[:d][1] = v.clamp(1,127)
      end
      puts "velocity #{count} clamped #{clamped}"
    when 'TEMPO'
      num, den = args.drop(1).map(&:to_i)
      raise 'bad argument' unless num.between?(1,1000) && den.between?(1,1000)
      events = ordered(song).map(&:first).select { |e| event_type(e) == 'TEMPO' }
      values = events.map { |e| (2*integer(e[:d])*den+num)/(2*num) }
      insert = !events.any? { |e| e[:t] == 0 }
      new_value = (1_000_000*den+num)/(2*num)
      raise 'tempo out of range' unless values.all? { |v| v.between?(1,16777215) } && (!insert || new_value.between?(1,16777215))
      events.zip(values).each { |e,v| e[:d] = big(v,3) }
      puts "scaled #{events.size}"
      if insert
        song[:tracks][0].unshift({t:0,s:255,m:81,d:big(new_value,3)})
        puts "inserted 0 0 TEMPO #{new_value}"
      end
    when 'FILTER'
      channels = args.drop(1).map(&:to_i)
      raise 'bad argument' unless channels.all? { |c| c.between?(1,16) }
      count = 0
      song[:tracks].each { |tr| tr.reject! { |e| drop = e[:s] < 240 && !channels.include?((e[:s]&15)+1); count += 1 if drop; drop } }
      puts "removed #{count}"
    when 'MERGE'
      raise 'not format 1' unless song[:f] == 1
      count = song[:tracks].size
      ending = {t:length(song),s:255,m:47,d:[]}
      song[:tracks] = [ordered(song).map(&:first).reject { |e| event_type(e) == 'END_OF_TRACK' } + [ending]]
      song[:f] = 0
      puts "merged #{count} tracks events #{song[:tracks][0].size}"
    when 'SPLIT'
      raise 'not format 0' unless song[:f] == 0
      track = song[:tracks][0]
      channels = track.select { |e| e[:s] < 240 }.map { |e| e[:s]&15 }.uniq.sort
      groups = {-1=>[]}.merge(channels.to_h { |c| [c,[]] })
      track[0...-1].each { |e| groups[e[:s] < 240 ? e[:s]&15 : -1] << e }
      song[:tracks] = groups.values.map { |tr| tr + [track[-1].dup] }
      song[:f] = 1
      puts "split tracks #{song[:tracks].size} events #{song[:tracks].sum(&:size)}"
    end
  rescue RuntimeError => e
    puts "error: #{e.message}"
  end
end
