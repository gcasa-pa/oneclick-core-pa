class Purpose < ApplicationRecord

  #### Includes ####
  include CharacteristicsHelper 

  ### ASSOCIATIONS
  belongs_to :agency
  has_many :trips
  has_and_belongs_to_many :services

  scope :for_superuser, -> {all}
  scope :for_oversight_user, -> (user) {where(agency: user.current_agency.agency_oversight_agency.pluck(:transportation_agency_id).concat([user.current_agency.id]))}
  scope :for_current_transport_user, -> (user) {where(agency: user.current_agency)}
  scope :for_transport_user, -> (user) {where(agency: user.staff_agency)}

  before_save :snake_casify, if: :has_code?
  validate :name_is_present?
  validates :name, uniqueness: {scope: :agency_id}

  def has_code?
    code.present?
  end

  def name_is_present?
    errors.add(:name, :blank) if self[:name].blank?
    errors.add(:name, :taken) if Purpose.where.not(id: id).exists?(name: self[:name], agency_id: agency_id)
  end

  def self.for_user(user)
    if user.superuser?
      for_superuser
    elsif user.currently_oversight?
      for_oversight_user(user)
    elsif user.currently_transportation?
      for_current_transport_user(user)
    elsif user.transportation_user?
      for_transport_user(user)
    else
      nil
    end
  end
end
