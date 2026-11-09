class Memory
  attr_reader :queue, :log, :capacity

  def initialize(capacity)
    @capacity = capacity
    @queue = []
    @log = []
  end

  def store(session, keyword, text)
    prefix = "#{session[:name]} #{session[:turns]}"
    if @queue.include?(text)
      @log << "#{prefix} SKIP #{keyword} #{text}"
      return
    end
    @log << "#{prefix} DROP #{@queue.shift}" if @queue.length == @capacity
    @queue << text
    @log << "#{prefix} STORE #{keyword} #{text}"
    session[:stores] += 1
  end

  def recall(session)
    text = @queue.shift
    @log << "#{session[:name]} #{session[:turns]} RECALL #{text}"
    session[:recalls] += 1
    text
  end

  def clear(name, turn)
    count = @queue.length
    unless count.zero?
      @queue.clear
      @log << "#{name} #{turn} CLEAR #{count}"
    end
    count
  end
end
