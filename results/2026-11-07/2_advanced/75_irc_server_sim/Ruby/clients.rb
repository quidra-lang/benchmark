class Client
  attr_reader :identifier, :hostname, :connection_time, :queue, :channels, :invites
  attr_accessor :nickname, :username, :realname, :invisible, :registered,
                :registration_time, :last_received, :last_speaking, :ping_sent,
                :tokens, :refill_time, :away, :received, :sent, :active

  def initialize(identifier, hostname, time, capacity)
    @identifier, @hostname, @connection_time = identifier, hostname, time
    @nickname = @username = @registration_time = @last_speaking = @ping_sent = @refill_time = nil
    @realname = @away = ''
    @invisible = @registered = false
    @last_received = time
    @tokens = capacity
    @queue, @channels, @invites = [], [], []
    @received = @sent = 0
    @active = true
  end

  def addressee = @nickname || '*'
  def prefix = "#{@nickname}!#{@username}@#{@hostname}"
  def mode = @invisible ? '+i' : '+'

  def use_token(time, capacity, interval)
    @refill_time = time + interval if @tokens == capacity
    @tokens -= 1
  end

  def refill(time, capacity, interval)
    return unless @refill_time == time
    @tokens += 1
    @refill_time = @tokens < capacity ? time + interval : nil
  end
end
