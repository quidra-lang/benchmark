class CommandError < StandardError
end
Order = Struct.new(:id, :trader, :kind, :side, :price, :trigger, :peak, :condition,
                   :quantity, :remaining, :visible, :filled, :value, :priority, :status, :history, keyword_init: true) do
  def active? = %w[PENDING OPEN PARTIAL].include?(status)
  def resting? = %w[OPEN PARTIAL].include?(status)
  def matches?(p) = price.nil? || (side == 'BUY' ? p <= price : p >= price)
  def triggered?(p) = side == 'BUY' ? p >= trigger : p <= trigger
  def line = "ORDER #{id} #{status} #{filled}/#{quantity}"
  def details
    text = "#{id} #{trader} #{kind} #{side} #{price || '-'} #{status} #{filled}/#{quantity} avg #{filled.zero? ? '-' : decimals(value * 100 / filled)}"
    trigger ? "#{text} trigger #{trigger}" : text
  end
end
Trader = Struct.new(:name, :bought, :sold, :cash, :fees, :limit) do
  def net = bought - sold
  def volume = bought + sold
  def pnl(mark) = cash + net * mark
  def line(mark) = "POSITION #{name} bought #{bought} sold #{sold} net #{net} cash #{cash} fees #{fees} pnl #{pnl(mark)}"
end
Trade = Struct.new(:number, :price, :quantity, :buy, :sell, :taker, :buy_fee, :sell_fee) do
  def line = "TRADE #{number} #{price} #{quantity} #{buy.id} #{buy.trader} #{sell.id} #{sell.trader}"
end
def decimals(n) = "#{n / 100}.#{(n % 100).to_s.rjust(2, '0')}"
class Engine
  def initialize
    @orders, @traders, @trades = {}, {}, []
    @maker = @taker = @band = @priority = 0
    @tick = @lot = 1
    @halted = false
  end
  def emit(*parts) = puts(parts.join(' '))
  def fail_if(condition, reason) = (raise CommandError, reason if condition)
  def opposite(side) = side == 'BUY' ? 'SELL' : 'BUY'
  def resting(side) = @orders.values.select { |o| o.side == side && o.resting? }
  def best(side) = resting(side).min_by { |o| [side == 'BUY' ? -o.price : o.price, o.priority] }
  def active(name) = @orders.values.select { |o| o.trader == name && o.active? }
  def register(name) = @traders[name] ||= Trader.new(name, 0, 0, 0, 0, nil)
  def order(id) = @orders.fetch(id) { raise CommandError, 'unknown order' }
  def trader(name) = @traders.fetch(name) { raise CommandError, 'unknown trader' }
  def last = @trades.last&.price
  def exposure(name, side, excluded = nil)
    t = @traders[name]
    (side == 'BUY' ? t.net : -t.net) + active(name).sum { |o| o.side == side && o != excluded ? o.remaining : 0 }
  end
  def risk(name, side, quantity, excluded = nil)
    t = @traders[name]
    fail_if(t && t.limit && exposure(name, side, excluded) + quantity > t.limit, 'risk limit')
  end
  def band(price) = fail_if(@band > 0 && last && (price - last).abs > @band, 'outside band')
  def levels(side)
    resting(side).group_by(&:price).sort_by { |p, _| side == 'BUY' ? -p : p }.map { |p, orders| [p, orders.sum(&:visible), orders.length] }
  end
  def cancel(o)
    o.history << "CANCEL #{o.remaining}"
    o.remaining, o.visible, o.status = 0, 0, 'CANCELLED'
    emit(o.line)
  end
  def match(o)
    while o.remaining > 0
      y = best(opposite(o.side))
      break unless y && o.matches?(y.price)
      if y.trader == o.trader
        emit('STP', y.id, y.remaining)
        y.history << "STP #{y.remaining}"
        y.remaining, y.visible, y.status = 0, 0, 'CANCELLED'
        next
      end
      q, p = [o.remaining, y.visible].min, y.price
      buy, sell = o.side == 'BUY' ? [o, y] : [y, o]
      bf, sf = o.side == 'BUY' ? [q * @taker, q * @maker] : [q * @maker, q * @taker]
      tr = Trade.new(@trades.length + 1, p, q, buy, sell, o, bf, sf)
      @trades << tr
      [o, y].each do |x|
        x.remaining -= q
        x.filled += q
        x.value += q * p
        x.history << "FILL #{tr.number} #{p} #{q}"
      end
      y.visible -= q
      bt, st = @traders[buy.trader], @traders[sell.trader]
      bt.bought += q
      bt.cash -= q * p + bf
      bt.fees += bf
      st.sold += q
      st.cash += q * p - sf
      st.fees += sf
      emit(tr.line)
      y.status = y.remaining.zero? ? 'FILLED' : 'PARTIAL'
      if y.remaining > 0 && y.visible.zero?
        @priority += 1
        y.priority = @priority
        y.visible = [y.peak, y.remaining].min
        h = y.remaining - y.visible
        y.history << "REFRESH #{y.visible} #{h}"
        emit('REFRESH', y.id, y.visible, h)
      end
    end
  end
  def finish(o, force = false)
    if o.remaining.zero?
      o.status = 'FILLED'
    elsif force || (o.kind == 'LIMIT' && o.condition != 'IOC') || %w[ICEBERG STOPLIMIT].include?(o.kind)
      @priority += 1
      o.priority = @priority
      o.visible = [o.peak || o.remaining, o.remaining].min
      o.status = o.filled.zero? ? 'OPEN' : 'PARTIAL'
      o.history << "REST #{o.price} #{o.visible}"
    else
      o.history << "EXPIRE #{o.remaining}"
      o.remaining, o.status = 0, 'CANCELLED'
    end
    emit(o.line)
  end
  def triggers
    loop do
      break unless last
      selected = @orders.values.select { |o| o.status == 'PENDING' && o.triggered?(last) }
      break if selected.empty?
      selected.each { |o| o.status = 'TRIGGERING' }
      selected.each do |o|
        emit('TRIGGER', o.id)
        o.history << 'TRIGGER'
        match(o)
        finish(o)
      end
    end
  end
  def submit(command, a)
    id, name, side = a[0, 3]
    p = r = peak = cond = nil
    case command
    when 'MARKET'
      q = a[3].to_i
    when 'STOP'
      r, q = a[3, 2].map(&:to_i)
    when 'STOPLIMIT'
      r, p, q = a[3, 3].map(&:to_i)
    else
      p, q = a[3, 2].map(&:to_i)
      peak = a[5].to_i if command == 'ICEBERG'
      cond = a[5] if command == 'LIMIT'
    end
    prices = [r, p].compact
    fail_if(@halted, 'halted')
    fail_if(@orders.key?(id), 'duplicate id')
    fail_if(prices.include?(0), 'invalid price')
    fail_if(q.zero?, 'invalid quantity')
    fail_if(prices.any? { |x| x % @tick != 0 }, 'invalid tick')
    fail_if(q % @lot != 0, 'invalid lot')
    o = Order.new(id: id, trader: name, kind: command, side: side, price: p, trigger: r, peak: peak, condition: cond,
    quantity: q, remaining: q, visible: 0, filled: 0, value: 0, priority: 0, status: 'INCOMING', history: ['ACCEPT'])
    fail_if(peak && (peak.zero? || peak > q || peak % @lot != 0), 'invalid peak')
    fail_if(r && last && o.triggered?(last), 'invalid trigger')
    band(p) if p
    risk(name, side, q)
    y = best(opposite(side))
    fail_if(cond == 'POSTONLY' && y && o.matches?(y.price), 'would cross')
    available = resting(opposite(side)).sum { |x| x.trader != name && o.matches?(x.price) ? x.remaining : 0 }
    fail_if(cond == 'FOK' && available < q, 'unfillable')
    register(name)
    @orders[id] = o
    if r
      o.status = 'PENDING'
      emit(o.line)
    else
      match(o) unless cond == 'POSTONLY'
      finish(o)
      triggers
    end
  end
  def replace(a)
    id, p, q = a[0], a[1].to_i, a[2].to_i
    fail_if(@halted, 'halted')
    o = order(id)
    fail_if(!o.resting?, 'not open')
    fail_if(p.zero?, 'invalid price')
    fail_if(q.zero?, 'invalid quantity')
    moved = p != o.price
    fail_if(moved && p % @tick != 0, 'invalid tick')
    fail_if(q % @lot != 0, 'invalid lot')
    fail_if(!moved && q == o.remaining, 'no change')
    band(p) if moved
    risk(o.trader, o.side, q, o) if q > o.remaining
    kept = !moved && q < o.remaining
    o.quantity = o.filled + q
    o.remaining = q
    o.history << "REPLACE #{p} #{q} #{kept ? 'kept' : 'lost'}"
    emit('REPLACE', id, kept ? 'kept' : 'lost')
    if kept
      o.visible = [o.visible, q].min
      emit(o.line)
    else
      o.price = p
      o.status = 'INCOMING'
      match(o)
      finish(o, true)
      triggers
    end
  end
  def bar(group)
    ps = group.map(&:price)
    "open #{ps.first} high #{ps.max} low #{ps.min} close #{ps.last} volume #{group.sum(&:quantity)}"
  end
  def execute(line)
    c, *a = line.split
    if %w[LIMIT MARKET STOP STOPLIMIT ICEBERG].include?(c)
      submit(c, a)
      return
    end
    case c
    when 'CANCEL'
      o = order(a[0])
      fail_if(!o.active?, 'not open')
      cancel(o)
    when 'REPLACE'
      replace(a)
    when 'CANCELALL'
      trader(a[0])
      os = active(a[0])
      emit(c, a[0], os.length)
      os.each { |o| cancel(o) }
    when 'HALT', 'RESUME'
      fail_if(c == 'HALT' ? @halted : !@halted, c == 'HALT' ? 'already halted' : 'not halted')
      @halted = c == 'HALT'
      emit(c)
    when 'RISK'
      register(a[0]).limit = a[1].to_i
      emit(c, *a, 'exposure buy', exposure(a[0], 'BUY'), 'sell', exposure(a[0], 'SELL'))
    when 'FEE'
      m, t = a.map(&:to_i)
      fail_if(m + t < 0, 'invalid fee')
      @maker, @taker = m, t
      emit(c, 'maker', m, 'taker', t)
    when 'BAND'
      @band = a[0].to_i
      emit(c, @band)
    when 'TICK', 'LOT'
      n = a[0].to_i
      fail_if(n.zero?, 'invalid size')
      c == 'TICK' ? @tick = n : @lot = n
      emit(c, n)
    when 'BOOK'
      n = a[0].to_i
      fail_if(n.zero?, 'invalid depth')
      bids, asks = levels('BUY'), levels('SELL')
      emit(c, 'bids', bids.length, 'asks', asks.length)
      asks.take(n).reverse_each { |v| emit('ASK', *v) }
      bids.take(n).each { |v| emit('BID', *v) }
    when 'ORDERS'
      trader(a[0])
      os = active(a[0])
      emit(c, a[0], os.length)
      os.each { |o| emit(o.details) }
    when 'STATUS'
      emit(c, order(a[0]).details)
    when 'HISTORY'
      o = order(a[0])
      emit(c, o.id, o.history.length)
      o.history.each { |h| emit(h) }
    when 'POSITION'
      emit(trader(a[0]).line(last || 0))
    when 'FILLS'
      trader(a[0])
      ts = @trades.select { |t| [t.buy.trader, t.sell.trader].include?(a[0]) }
      emit(c, a[0], ts.length)
      net = 0
      ts.each do |t|
        buy = t.buy.trader == a[0]
        o = buy ? t.buy : t.sell
        net += buy ? t.quantity : -t.quantity
        emit(t.number, o.side, t.price, t.quantity, o.id, t.taker == o ? 'TAKER' : 'MAKER', 'fee', buy ? t.buy_fee : t.sell_fee, 'net', net)
      end
    when 'LAST'
      emit(c, *(@trades.empty? ? ['none'] : [last, @trades.last.quantity]))
    when 'VWAP'
      if @trades.empty?
        emit(c, 'none')
      else
        v = @trades.sum(&:quantity)
        emit(c, decimals(@trades.sum { |t| t.price * t.quantity } * 100 / v), 'volume', v, 'trades', @trades.length)
      end
    when 'SPREAD'
      b, s = best('BUY'), best('SELL')
      text = "SPREAD bid #{b&.price || 'none'} ask #{s&.price || 'none'}"
      text += " spread #{s.price - b.price} mid #{(b.price + s.price) / 2}.#{(b.price + s.price).odd? ? 5 : 0}" if b && s
      emit(text)
    when 'IMPACT'
      side, q = a[0], a[1].to_i
      fail_if(q.zero?, 'invalid quantity')
      ls = levels(opposite(side))
      r, cost, used, worst = q, 0, 0, 0
      ls.each do |p, v, _|
        break if r.zero?
        u = [r, v].min
        r -= u
        cost += u * p
        used += 1
        worst = p
      end
      emit(c, side, q, *(r > 0 ? ['insufficient', ls.sum { |v| v[1] }] : ['avg', decimals(cost * 100 / q), 'worst', worst, 'levels', used]))
    when 'TRADES', 'BARS'
      k = a[0].to_i
      fail_if(k.zero?, 'invalid count')
      if c == 'TRADES'
        ts = @trades.last(k)
        emit(c, ts.length, 'of', @trades.length)
        ts.each { |t| emit(t.line) }
      else
        groups = @trades.each_slice(k).to_a
        emit(c, groups.length)
        groups.each_with_index { |g, i| emit(i + 1, bar(g)) }
      end
    when 'RANK'
      ts = @traders.values.sort_by { |t| [-t.pnl(last || 0), -t.volume, t.name] }
      emit(c, ts.length)
      ts.each_with_index { |t, i| emit(i + 1, t.name, 'pnl', t.pnl(last || 0), 'volume', t.volume) }
    when 'FLOW'
      b = @trades.sum { |t| t.taker.side == 'BUY' ? t.quantity : 0 }
      s = @trades.sum { |t| t.taker.side == 'SELL' ? t.quantity : 0 }
      emit(c, 'buy', b, 'sell', s, 'net', b - s)
    when 'SUMMARY'
      if @trades.empty?
        emit(c, 'trades', 0)
      else
        ps = @trades.map(&:price)
        emit(c, 'trades', @trades.length, 'volume', @trades.sum(&:quantity), 'open', ps.first, 'high', ps.max, 'low', ps.min, 'close', ps.last, 'fees', @trades.sum { |t| t.buy_fee + t.sell_fee })
      end
      @traders.keys.sort.each { |name| emit(@traders[name].line(last || 0)) }
    end
  rescue CommandError => e
    emit(*(%w[LIMIT MARKET STOP STOPLIMIT ICEBERG CANCEL REPLACE].include?(c) ? ['REJECT', a[0]] : ['ERROR']), e.message)
  end
end
engine = Engine.new
STDIN.gets.to_i.times { engine.execute(STDIN.gets) }
