module Materials
  def self.read(path = 'input/materials.txt')
    File.readlines(path).map do |line|
      code, name, k, rho, cp = line.split
      { code: code, name: name, k: k.to_f, rho: rho.to_f, cp: cp.to_f }
    end
  end

  def self.capacity(material, dx, d) = material[:rho] * material[:cp] * dx * dx * d
  def self.interior(k1, k2, d) = 2 * k1 * k2 / (k1 + k2) * d
  def self.fixed(k, d) = 2 * k * d
  def self.convective(k, h, dx, d) = 1 / (1 / (h * dx * d) + 1 / (2 * k * d))
end
