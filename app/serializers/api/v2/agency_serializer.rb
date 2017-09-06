module Api
  module V2
    class AgencySerializer < ActiveModel::Serializer
      attributes  :id, :name, :type, :logo, :phone, :formatted_phone, :email, :url, :comments
      
      def self.collection_serialize(collection)
        ActiveModelSerializers::SerializableResource.new(collection, each_serializer: self)
      end

      def logo
        object.full_logo_url
      end
      
      def comments
        object.comments_hash
      end
      
    end
  end
end