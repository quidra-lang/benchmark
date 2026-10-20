module Ledger
  StoredBlock = Struct.new(:block, :parent, :work, :utxo, :fees, :transaction_fees, :source,
                           keyword_init: true)

  class Chain
    def initialize(settings)
      @initial_difficulty = settings.fetch('DIFFICULTY')
      @interval, @target = settings.fetch('RETARGET')
      @initial_reward, @halving = settings.fetch('REWARD')
    end

    def reward(height)
      amount = @initial_reward
      (height / @halving).times { amount /= 2 }
      amount
    end

    def ancestor(record, height)
      record = record.parent while record.block.height > height
      record
    end

    def sequence(record)
      result = []
      while record
        result << record
        record = record.parent
      end
      result.reverse
    end

    def fork(first, second)
      first = first.parent while first.block.height > second.block.height
      second = second.parent while second.block.height > first.block.height
      until first.block.id == second.block.id
        first = first.parent
        second = second.parent
      end
      first
    end

    def median_time(record)
      timestamps = []
      while record && timestamps.length < 3
        timestamps << record.block.timestamp
        record = record.parent
      end
      timestamps.sort[(timestamps.length - 1) / 2]
    end

    def required(record)
      height = record.block.height + 1
      return @initial_difficulty if height == 1
      return record.block.difficulty unless (height % @interval).zero?

      earlier = ancestor(record, height - @interval)
      span = record.block.timestamp - earlier.block.timestamp
      expected = @target * (@interval - 1)
      if 2 * span < expected
        [record.block.difficulty + 1, 2].min
      elsif span > 2 * expected
        [record.block.difficulty - 1, 0].max
      else
        record.block.difficulty
      end
    end
  end
end
