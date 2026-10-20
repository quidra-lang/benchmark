require 'csv'

Image = Data.define(:id, :label, :pixels, :vector)

class MINSTD
  def initialize(seed) = @state = seed
  def draw = @state = 48_271 * @state % 2_147_483_647
  def shuffle(values)
    values.size.downto(2) do |i|
      j = draw % i
      values[i - 1], values[j] = values[j], values[i - 1]
    end
    values
  end
end

def read_images(path)
  CSV.read(path, headers: true).map { |r| Image.new(r['id'], r['label'].to_i, r['pixels'], r['pixels'].chars.map(&:to_f)) }
end

def load_inputs
  dimensions, *blocks = File.read('input/network.txt').strip.split("\n\n")
  _, width, height = dimensions.split
  networks = blocks.map do |block|
    first, *lines = block.lines.map(&:split)
    { name: first[1], width: width.to_i, height: height.to_i,
      layers: lines.map { |kind, units, activation| { kind: kind, units: units.to_i, activation: activation } } }
  end
  weights = {}
  File.read('input/weights.txt').strip.split("\n\n").each do |block|
    first, *lines = block.lines.map(&:split)
    weights[first[1]] = lines.select { |v| ['W', 'B'].include?(v[0]) }.flat_map { |v| v.drop(1).map(&:to_f) }
  end
  settings = { runs: [] }
  File.foreach('input/params.txt') do |line|
    keyword, *v = line.split
    case keyword
    when 'RUN'
      name, network, optimizer, rate, decay, *extra = v
      settings[:runs] << { name: name, network: network, optimizer: optimizer, rate: rate.to_f, decay: decay.to_f, extra: extra.map(&:to_f) }
    when 'LR_STEP' then settings[:lr_step], settings[:lr_gamma] = v[0].to_i, v[1].to_f
    when 'PRUNE', 'NOISE' then settings[keyword.downcase.to_sym] = v.map(&:to_i)
    else settings[keyword.downcase.to_sym] = v[0].to_i
    end
  end
  [read_images('input/train.csv'), read_images('input/test.csv'), networks, weights, settings]
end
