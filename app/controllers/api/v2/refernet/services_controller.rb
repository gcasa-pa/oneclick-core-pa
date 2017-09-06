module Api
  module V2
    module Refernet
      class ServicesController < ApiController
      
        # Overwrite the services index call in refernet so that we can add transportation info
        def index
          data = []
          duration_hash = {}
          
          sub_sub_category = OneclickRefernet::SubSubCategory.find_by(name: params[:sub_sub_category])
          
          if params[:lat] and params[:lng]
            duration_hash = build_duration_hash(params, sub_sub_category)
          end

          sub_sub_category.try(:services).try(:confirmed).each do |service|
            svc_data = service_hash(service, duration_hash)
            data << svc_data
          end 

          render json: data

        end

        protected

        # Builds the request to be sent to OTP
        def build_request origin, service, mode="TRANSIT,WALK"

          {
            from: [
              origin[0],
              origin[1]
            ],
            to: [
              service.lat,
              service.lng
            ],
            trip_time:  Time.now,
            arrive_by: true,
            label: "#{service.id}_#{mode}",
            options: {
              mode: mode,
              num_itineraries: 1
            }
          }
        end

        # Acts as a serializer for refernet services
        def service_hash service, duration_hash={}
          { "service_id": service["Service_ID"],
            "agency_name": service['agency_name'],
            "site_name": service['site_name'],
            "lat": service.lat,
            "lng": service.lng,
            "address": service.address,
            "phone": service['details']["Number_Phone1"],
            "drive_time": duration_hash["#{service.id}_CAR"],
            "transit_time": duration_hash["#{service.id}_TRANSIT,WALK"],
            "url": service['details']['url'],
            "description":  service['details']["Label_Service Description"] || "#{service['details']['Note1']} #{service['details']['Note2']}" 
          }
        end

        # Call OTP and Pull out the durations
        def build_duration_hash(params, sub_sub_category)
          duration_hash ={}
          origin = [params[:lat], params[:lng]]
          otp = OTPServices::OTPService.new(Config.open_trip_planner)
            
          ### Build the requests
          requests = []
          sub_sub_category.try(:services).try(:confirmed).each do |service|
            ['TRANSIT,WALK', 'CAR'].each do |mode|
              requests << build_request(origin, service, mode)
            end 
          end         
            
          ### Make the Call
          plans = otp.multi_plan([requests])

          ### Unack the requests and build a hash of durations
          plans[:callback].each do |label, plan|
            response = otp.unpack(plan.response)
            itinerary = response.extract_itineraries.first
            duration_hash[label] = itinerary.nil? ? nil : itinerary.itinerary["duration"]
          end

          duration_hash
        end
      
      end
    end
  end
end