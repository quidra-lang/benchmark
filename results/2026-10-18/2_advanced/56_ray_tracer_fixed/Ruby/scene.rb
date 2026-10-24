require_relative 'vector3'

Material = Struct.new(:name, :color, :kd, :ks, :n, :kr, :kt, :ior, :checker)

class Scene
  include Vector3
  attr_reader :materials, :objects, :lights, :fog, :eye, :forward, :right,
              :up, :view, :background, :ambient

  def initialize(path)
    @materials, @objects, @lights = {}, [], []
    @fog = nil
    File.foreach(path, chomp: true) do |line|
      next if line.empty? || line.start_with?('#')
      kind, *words = line.split
      case kind
      when 'material'
        name = words.shift
        values = words.map(&:to_i)
        @materials[name] = Material.new(name, values[0, 3], *values[3, 6], nil)
      when 'checker'
        name = words.shift
        values = words.map(&:to_i)
        @materials.fetch(name).checker = [values[0, 3], values[3]]
      when 'sphere', 'plane', 'box'
        read_object(kind, words)
      when 'point', 'spot', 'sun', 'area'
        read_light(kind, words.map(&:to_i))
      when 'ambient'
        @ambient = words[0].to_i
      else
        instance_variable_set("@#{kind}", words.map(&:to_i))
      end
    end
  end

  def read_object(kind, words)
    label, name, *values = words
    values = values.map(&:to_i)
    obj = { number: @objects.length + 1, kind: kind, label: label,
            material: @materials.fetch(name) }
    case kind
    when 'sphere' then obj.merge!(center: values[0, 3], radius: values[3])
    when 'plane' then obj.merge!(point: values[0, 3], normal: norm(values[3, 3]))
    when 'box' then obj.merge!(lo: values[0, 3], hi: values[3, 3])
    end
    @objects << obj
  end

  def read_light(kind, values)
    light = { number: @lights.length + 1, kind: kind, intensity: values[-1], samples: 1 }
    if kind == 'sun'
      light[:direction] = norm(neg(values[0, 3]))
    else
      light[:position] = values[0, 3]
      if kind == 'spot'
        light.merge!(direction: norm(values[3, 3]), outer: values[6], inner: values[7])
      elsif kind == 'area'
        light.merge!(u: values[3, 3], v: values[6, 3], divisions: values[9], samples: values[9]**2)
      end
    end
    @lights << light
  end
end
