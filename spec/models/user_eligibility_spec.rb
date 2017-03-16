require 'rails_helper'

RSpec.describe UserEligibility, type: :model do
  let!(:traveler) { FactoryGirl.create :user }
  let!(:user_eligibility) { FactoryGirl.create :user_eligibility, :confirmed, user: traveler}

  it { should belong_to :user }
  it { should belong_to :eligibility }
  it { should respond_to :value }

  it 'returns an api_hash' do
    expect(user_eligibility.api_hash[:code]).to eq(user_eligibility.eligibility.code)
    expect(user_eligibility.api_hash[:note]).to eq('missing key ' + user_eligibility.eligibility.code + '_note')
    expect(user_eligibility.api_hash[:name]).to eq('missing key ' + user_eligibility.eligibility.code + '_name')
    expect(user_eligibility.api_hash[:value]).to eq(true)
  end
end