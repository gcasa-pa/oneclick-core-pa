class TrapezeAmbassador < BookingAmbassador

  attr_accessor :url, :api_user, :api_token, :client_code
  
  # Calls super and then sets proper default for URL and Token
  def initialize(opts={})
    super(opts)
    @url ||= Config.trapeze_url
    @api_user ||= Config.trapeze_user
    @api_token ||= Config.trapeze_token
    @client = create_client(Config.trapeze_url, Config.trapeze_url, @api_user, @api_token)
    @client_code = nil #Will be filled out after logging in
    @cookies = nil #Cookies are used to login the user
    @passenger_types = nil # A list of all passengers types allowed for this user.  It's saved to avoid making the call multiple times.
    @booking_id = nil
  end

  #####################################################################
  ## Top-level required methods in order for BookingAmbassador to work
  #####################################################################
  # Returns symbol for identifying booking api type
  def booking_api
    :trapeze
  end

  # Used to test if a Oneclick Service is setup correctly
  def authentic_provider?
    #TODO: Call Trapeze to Confirm that the ProviderID exists before allowing a Service to set it's ID
    true
  end

  # Returns True if a User is a valid Trapeze User
  def authenticate_user?
    response = pass_validate_client_password
    if response.to_hash[:pass_validate_client_password_response][:validation][:item][:code] == "RESULTOK"
      return true
    else
      return false
    end
  end

  def book
    # select the itinerary if not already selected
    @itinerary.select if @itinerary && !@itinerary.selected?

    # Make a create_trip call to Trapeze, passing a trip and any 
    # booking_options that have been set
    response = pass_create_trip

    return false unless response && response[:pass_create_trip_response][:pass_create_trip_result][:booking_id].to_s != "-1"
        
    # Store the status info in a Booking object and return it
    set_booking_id(response)
    update_booking

    return booking
  end

  def cancel
    pass_cancel_trip
    # Unselect the itinerary on successful cancellation
    @itinerary.unselect
    # Update Booking object with status info and return it
    update_booking
    return booking
  end

  def status
  end

  # Returns an array of question objects for RidePilot booking
  def prebooking_questions

    if @url.blank? or @api_token.blank?
      return []
    end

    [
      {
        question: "What is your trip purpose?", 
        choices: purpose_choices, 
        code: "purpose"
      },
      {
        question: "Are you traveling with anyone?", 
        choices: passenger_choices, 
        code: "guests"
      },
    ]
  end

  #####################################################################
  ## SOAP Calls to Trapeze
  #####################################################################
  def pass_validate_client_password
    begin
      response = @client.call(:pass_validate_client_password, message: {client_id: customer_id, password: customer_token})
    rescue => e
      Rails.logger.error e.message 
      return false
    end
    Rails.logger.info response.to_hash
    return response 
  end

  # Books the passed trip via RidePilot
  def pass_create_trip
    # Only attempt to create trip if all the necessary pieces are there
    return false unless @itinerary && @trip && @service && @user
    login if @cookies.nil? 
    puts trip_hash.ai 
    @client.call(:pass_create_trip, message: trip_hash, cookies: @cookies).to_hash
  end

  # Get Client Info
  def pass_get_client_info
    login if @cookies.nil? 
    response = @client.call(:pass_get_client_info, message: {client_id: customer_id, password: customer_token}, cookies: @cookies)
    Rails.logger.info response.to_hash
    return response.to_hash[:pass_get_client_info_response]
  end

  # Cancel the trip
  def pass_cancel_trip
    login if @cookies.nil? 
    message = {booking_id: booking_id, sched_status: 'CA'}
    @client.call(:pass_cancel_trip, message: message, cookies: @cookies).hash
  end

  # Get Trip Purposes for the specific user
  def pass_get_booking_purposes
    login if @cookies.nil?

    # Don't return trip purposes for a non-logged in user
    return nil if @cookies.nil?

    @client.call(:pass_get_booking_purposes, cookies: @cookies).hash
  end

  # Get a List of Passenger Types
  def pass_get_passenger_types
    #Login
    login if @cookies.nil?
    return nil if @cookies.nil?
    
    return @passenger_types unless @passenger_types.nil?
    message = {client_id: customer_id}
    @passenger_types = @client.call(:pass_get_passenger_types, message: message, cookies: @cookies).hash
    return @passenger_types
  end
  
  # Get Client Trips
  def pass_get_client_trips from_date=nil, to_date=nil, booking_id=nil
    login if @cookies.nil?
    message = {}

    #Add the parameters to the request.
    if from_date 
      message[:from_date] = from_date.strftime("%Y%m%d")
    end
    if to_date 
      message[:to_date] = to_date.strftime("%Y%m%d")
    end
    if booking_id
      message[:booking_id] = booking_id
    end

    @client.call(:pass_get_client_trips, message: message, cookies: @cookies).hash
  end

  #####################################################################
  ## Helper Methods
  #####################################################################
  # Gets the customer id from the user's booking profile
  def customer_id
    @booking_profile.try(:external_user_id)
  end

  # Gets the customer token from the user's booking profile  b
  def customer_token
    @booking_profile.try(:external_password)
  end

  # Return the Trapeze ID of the Service
  def para_service_id
    return nil unless @service
    @service.booking_details["trapeze_provider_id"]
  end

  # Login the Client
  def login
    return false unless (customer_id and customer_token) 
    result = pass_validate_client_password
    @cookies = result.http.cookies
    @client_code = result.to_hash[:pass_validate_client_password_response][:pass_validate_client_password_result][:client_code]
    true 
  end

  # Build a Trapeze Place Hash for the Origin
  def origin_hash
    if @itinerary.nil?
      return nil
    end
    place_hash @itinerary.trip.origin
  end

  # Build a Trapeze Place Hash for the Destination
  def destination_hash
    if @itinerary.nil?
      return nil
    end
    place_hash @itinerary.trip.destination
  end

  # Pass an OCC Place, get a Trapeze Place
  def place_hash place
    {
      address_mode: 'ZZ', 
      street_no: (place.street_number || "").upcase, 
      on_street: (place.route || "").upcase, 
      unit: ("").upcase, 
      city: (place.city|| "").upcase, 
      state: (place.state || "").upcase, 
      zip_code: place.zip, 
      lat: (place.lat*1000000).to_i, 
      lon: (place.lng*1000000).to_i, 
      geo_status:  -2147483648 
    }
  end

  # Builds the payload for creating a trip
  def trip_hash

     # Create Pickup/Dropoff Hashes
    if @trip.arrive_by
      pu_leg_hash = {request_address: origin_hash}
      do_leg_hash = {req_time: @trip.trip_time.in_time_zone.seconds_since_midnight, request_address: destination_hash}
    else
      do_leg_hash = {request_address: destination_hash}
      pu_leg_hash = {req_time: @trip.trip_time.in_time_zone.seconds_since_midnight, request_address: origin_hash}
    end
    
    request_hash = {
      client_id: customer_id.to_i, 
      client_code: @client_code, 
      date: @trip.trip_time.strftime("%Y%m%d"), 
      booking_type: 'C', 
      para_service_id: para_service_id, 
      auto_schedule: true, 
      calculate_pick_up_req_time: true, 
      booking_purpose_id: @booking_options[:purpose], 
      pick_up_leg: pu_leg_hash, 
      drop_off_leg: do_leg_hash
    }

    # Check to see if another passenger is coming
    if @booking_options[:guests] != "NONE"
      request_hash[:companion_mode] = "S"
      request_hash[:pass_booking_passengers] = [passenger_hash(@booking_options[:guests])]
    end

    return request_hash
  
  end

  #TODO: This is not used right now.  Should it be?
  def get_funding_source_array
    ada_funding_sources = Config.trapeze_ada_funding_sources
    ignore_polygon = Config.trapeze_ignore_polygon_id
    check_polygon = Config.trapeze_check_polygon_id
  end

  def set_booking_id response
    @booking_id = response.try(:with_indifferent_access).try(:[], "pass_create_trip_response").try(:[], "pass_create_trip_result").try(:[], "booking_id")
  end

  # Gets the Trapeze Booking Id from the booking object
  def booking_id
    @booking_id || booking.try(:confirmation)
  end

  # Builds an array of allowed purposes to ask the user.  
  def purpose_choices
    result = pass_get_booking_purposes
    return [] if result.nil?
    result.to_hash[:envelope][:body][:pass_get_booking_purposes_response][:pass_get_booking_purposes_result][:pass_booking_purpose].map{|v| [v[:description], v[:booking_purpose_id]]}
  end

  # Builds an array of allowed passengers types.  Used to ask the user about passenger.
  def passenger_choices
    passenger_choices_array = [["NONE", "NONE"]]
    ##result = pass_get_passenger_types
    passenger_types_array.each do |purpose|
      passenger_choices_array.append([purpose.try(:[], :description), purpose.try(:[], :abbreviation)])
    end
    passenger_choices_array
  end

  # returns a hash of booking attributes from a RidePilot response
  def booking_attrs
    response = pass_get_client_trips(nil, nil, booking_id)
    {
      type: "TrapezeBooking",
      details: response.try(:with_indifferent_access),
      status:  response.try(:with_indifferent_access).try(:[], :envelope).try(:[], :body).try(:[], :pass_get_client_trips_response).try(:[], :pass_get_client_trips_result).try(:[], :pass_booking).try(:[], :sched_status),
      confirmation: booking_id
    }
  end

  # Updates trip booking object with response
  def update_booking
    booking.try(:update_attributes, booking_attrs)
  end


  # Builds a hash for bringing extra passengers 
  def passenger_hash passenger
    # Get the fare_type for this passenger from the mapping
    fare_type = passenger_type_funding_type_mapping[passenger]

    {pass_booking_passenger: {passenger_type: passenger, space_type: "AM", passenger_count: 1, fare_type: fare_type}}
  end

  # Passenger Type to Funding Type Mapping
  # Each extra passenger type, must have it's own funding type.
  # 
  def passenger_type_funding_type_mapping
    mapping = {}
    passenger_types_array.each do |pass|
      mapping[pass.try(:with_indifferent_access).try(:[], :abbreviation)] = pass.try(:with_indifferent_access).try(:[], :fare_type_id)
    end
    mapping
  end

  def passenger_types_array 
    result = pass_get_passenger_types
    return [] if result.nil?
    result.try(:with_indifferent_access).try(:[], :envelope).try(:[], :body).try(:[], :pass_get_passenger_types_response).try(:[], :pass_get_passenger_types_result).try(:[], :pass_passenger_type)
  end

  protected

  # Create a Client
  def create_client(endpoint, namespace, username, password)
    client = Savon.client do
      endpoint endpoint
      namespace namespace
      basic_auth [username, password]
      convert_request_keys_to :camelcase
    end
    client
  end

end