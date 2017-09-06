module Api
  module V2

    class ItinerarySerializer < ActiveModel::Serializer
      
      attributes :trip_type,
        :cost,
        :walk_time,
        :transit_time,
        :walk_distance,
        :wait_time,
        :legs
    
      belongs_to :service
      
    end
    
  end
end