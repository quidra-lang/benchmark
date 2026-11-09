module Postprocess
  Result = Data.define(:name, :displacement, :forces, :reactions, :external)

  def self.axial_forces(geometry, properties, displacement, temperature, removed = nil)
    forces = Array.new(geometry.length, 0.0)
    geometry.zip(properties).each_with_index do |(shape, member), number|
      next if number == removed

      ix, iy, jx, jy = shape.dofs
      extension = (displacement[jx] - displacement[ix]) * shape.cosine +
                  (displacement[jy] - displacement[iy]) * shape.sine
      forces[number] = member.stiffness * extension - temperature[number]
    end
    forces
  end

  def self.reactions(matrix, displacement, force, restrained)
    result = Array.new(force.length, 0.0)
    restrained.each do |row|
      value = 0.0
      force.length.times { |column| value += matrix[row][column] * displacement[column] }
      result[row] = value - force[row]
    end
    result
  end

  def self.superpose(combination, results)
    name, factor = combination.terms.first
    fields = %i[displacement forces reactions external]
    vectors = fields.map { |field| results[name].public_send(field).map { |value| factor * value } }
    combination.terms.drop(1).each do |case_name, coefficient|
      vectors.zip(fields.map { |field| results[case_name].public_send(field) }).each do |target, source|
        source.each_with_index { |value, index| target[index] += coefficient * value }
      end
    end
    Result.new(combination.name, *vectors)
  end

  def self.equilibrium_residual(result, geometry)
    residual = result.external.zip(result.reactions).map { |external, reaction| external + reaction }
    geometry.zip(result.forces).each do |shape, force|
      direction = [shape.cosine, shape.sine, -shape.cosine, -shape.sine]
      shape.dofs.zip(direction).each { |degree, coefficient| residual[degree] += force * coefficient }
    end
    residual.map(&:abs).max
  end
end
