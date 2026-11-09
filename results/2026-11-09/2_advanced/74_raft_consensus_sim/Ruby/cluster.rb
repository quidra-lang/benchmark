Control = Data.define(:time, :kind, :arguments)
Settings = Data.define(:nodes, :election_min, :election_max, :heartbeat, :batch,
                      :quorum, :seed, :end_time, :retry, :attempts, :sample)

class Request
  attr_reader :number, :time, :initial_destination, :command
  attr_accessor :scheduled, :destination, :attempts, :redirects, :accepted,
                :abandoned, :status, :latency, :result

  def initialize(number, time, destination, command)
    @number, @time, @initial_destination, @command = number, time, destination, command
    @scheduled, @destination = time, destination
    @attempts = @redirects = 0
    @accepted = @status = @latency = @result = nil
    @abandoned = false
  end
end

module Cluster
  def self.read_settings(path = 'input/cluster.txt')
    values = File.readlines(path, chomp: true).to_h do |line|
      key, *numbers = line.split
      [key, numbers.map(&:to_i)]
    end
    Settings.new(values['NODES'][0], *values['ELECTION'], values['HEARTBEAT'][0],
                 values['BATCH'][0], values['QUORUM'][0], values['SEED'][0],
                 values['END'][0], values['RETRY'][0], values['ATTEMPTS'][0], values['SAMPLE'][0])
  end

  def self.read_script(path = 'input/script.txt')
    controls, requests = [], []
    File.foreach(path) do |line|
      time, kind, *arguments = line.split
      if kind == 'REQUEST'
        destination, *command = arguments
        command[2] = command[2].to_i if command.length == 3
        requests << Request.new(requests.length + 1, time.to_i, destination.to_i, command.freeze)
      else
        arguments = if kind == 'PARTITION'
                      arguments.map { |group| group.split(',').map(&:to_i) }
                    else
                      arguments.map(&:to_i)
                    end
        controls << Control.new(time.to_i, kind, arguments)
      end
    end
    [controls, requests]
  end
end
