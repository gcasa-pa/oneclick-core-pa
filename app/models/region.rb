class Region < ApplicationRecord
  include GeoKitchen
  include LeafletAmbassador

  ### Attributes ###
  serialize :recipe, GeoRecipe
  make_attribute_mappable :geom

  ### Callbacks ###
  before_save :build_geometry_from_recipe

  ### Methods ###
  def contains?(other_geom)
    if(other_geom.is_a?(Place))
      other_geom = other_geom.to_point
    end
    geom.contains?(other_geom)
  end

  private

  def build_geometry_from_recipe
    self.geom = recipe.make
    unless recipe.errors.empty?
      recipe.errors.each do |e|
        @errors.add(:recipe, e)
      end
    end
  end

end