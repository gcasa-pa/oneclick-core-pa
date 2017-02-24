require 'rails_helper'

RSpec.describe Api::ApiController, type: :controller do
  # This line is necessary to get Devise scoped tests to work.
  before(:each) { @request.env["devise.mapping"] = Devise.mappings[:user] }
  let(:user) { create(:user) }
  let(:request_headers) { {"X-USER-EMAIL" => user.email, "X-USER-TOKEN" => user.authentication_token} }

  it 'authenticates user from token & sets @traveler' do
    expect(controller.traveler).to be_nil

    request.headers.merge!(request_headers) # Send user email and token headers
    controller.authenticate_user_from_token!

    expect(controller.traveler.email).to eq(request.headers["X-User-Email"])
  end

  it 'authenticates user if token present' do
    expect(controller.traveler).to be_nil

    request.headers.merge!(request_headers) # Send user email and token headers
    controller.authenticate_user_if_token_present

    expect(controller.traveler.email).to eq(request.headers["X-User-Email"])
  end

  it 'does not authenticate user if token not present' do
    expect(controller.traveler).to be_nil

    controller.authenticate_user_if_token_present

    expect(controller.traveler).to be_nil
  end

end