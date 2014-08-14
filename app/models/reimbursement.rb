#
# Reimbursement for a given request
#
class Reimbursement < ActiveRecord::Base
  include HasState

  # The associated request
  belongs_to :request, :inverse_of => :reimbursement
  # Comments used to discuss decisions (private) or communicate with the requester (public)
  has_many :comments, :as => :machine, :dependent => :destroy
  # The expenses of the associated request, total_amount and authorized_amount
  # will be updated during reimbursement process
  has_many :expenses, :through => :request, :autosave => false
  # Attachments for providing invoices and reports
  has_many :attachments, :class_name => "ReimbursementAttachment", :inverse_of => :reimbursement, :dependent => :destroy
  # Links pointing to reports (ie., blog posts) regarding the requester
  # participation in the event
  has_many :links, :class_name => "ReimbursementLink", :inverse_of => :reimbursement, :dependent => :destroy
  # Can have several payments, not related to the number of expenses
  has_many :payments, :inverse_of => :reimbursement, :dependent => :restrict_with_exception
  # Bank information goes to another model
  has_one :bank_account, :inverse_of => :reimbursement, :dependent => :destroy, :autosave => true

  delegate :event, :to => :request, :prefix => false

  accepts_nested_attributes_for :request, :update_only => true,
    :allow_destroy => false, :reject_if => :reject_request

  accepts_nested_attributes_for :attachments, :allow_destroy => true

  accepts_nested_attributes_for :links, :allow_destroy => true

  accepts_nested_attributes_for :bank_account, :allow_destroy => false

  validates :request, :presence => true
  validates_associated :expenses, :attachments, :links, :bank_account
  validates :acceptance_file, :presence => true, :if => "acceptance_file_required?"
  validate :user_profile_is_complete, :if => "complete_profile_required?"

  mount_uploader :acceptance_file, AttachmentUploader

  auditable :except => [:acceptance_file]

  # Synchronizes user_id and request_id
  before_validation :set_user_id
  before_validation :ensure_bank_account


  # @see HasState.responsible_roles
  self.responsible_roles = [:tsp, :assistant]
  # @see HasState.assign_state
  assign_state :incomplete, :to => :requester
  assign_state :submitted, :to => :tsp
  assign_state :approved, :to => :administrative


  # Checks if user role can cancel the reimbursement
  #
  # @param [Role] user role to be checked
  # @return [Boolean] true if role can cancel
  def cancel_role?(role)
    [1,2,3].include?(role.id)
  end

  # @see Request#expenses_sum
  def expenses_sum(*args)
    request.expenses_sum(*args)
  end

  # @see Request.expenses_sum
  def self.expenses_sum(attr = :total, reimbursements)
    if reimbursements.kind_of?(ActiveRecord::Relation)
      r_ids = reimbursements.reorder("").pluck("reimbursements.request_id")
    else
      r_ids = reimbursements.map(&:request_id)
    end
    Request.expenses_sum(attr, r_ids)
  end

  # Checks whether a tsp user should be allowed to cancel
  #
  # No special case, simply call to #can_cancel?
  #
  # @return [Boolean] true if allowed
  def cancelable_by_tsp?
    can_cancel?
  end

  # Checks whether can have a transition to 'canceled' state
  #
  # Overrides the HasState.can_cancel?, preventing cancelation of reimbursements
  # that have already been processed
  # @see HasState.can_cancel?
  #
  # return [Boolean] true if #cancel can be called
  def can_cancel?
    not canceled? and not processed? and not payed?
  end

  # Checks whether the acceptance file is required in order to be a valid
  # reimbursement
  #
  # @return [Boolean] true if signed acceptance is required
  def acceptance_file_required?
    not (incomplete? || canceled?)
  end

  # Checks whether a complete user profile (with the required information
  # filled) is required in order to be a valid reimbursement. A complete profile
  # is not required if the reimbursement is being rolled back, only
  # when trying to go further into the workflow.
  #
  # @return [Boolean] true if the profile have to be complete
  def complete_profile_required?
    (submitted? && state_was == "incomplete") ||
      (approved? && state_was == "submitted")
  end

  # Label to identify the reimbursement
  #
  # Overrides the default method to use the request id instead of the internal
  # reimbursement id.
  #
  # @return [String] label based in the id of the associated request
  def label
    "##{request_id}"
  end

  protected

  # Used internally to synchronize request_id and user_id
  def set_user_id
    self.user_id = request.user_id
  end

  def ensure_bank_account
    build_bank_account if bank_account.nil?
  end

  # Validates the existance of a complete profile
  def user_profile_is_complete
    unless user.profile.complete?
      errors.add(:user, :incomplete)
    end
  end

  # Used internally by accepts_nested_attributes to ensure that only
  # total_amount and authorized_amount are accessible through the reimbursement
  #
  # _delete keys are also rejected, so expenses cannot either be deleted
  #
  # @return [Boolean] true if the request should be rejected
  def reject_request(attrs)
    acceptable_request_attrs = %w(id expenses_attributes)
    acceptable_expenses_attrs = %w(id total_amount authorized_amount)
    return true unless (attrs.keys - acceptable_request_attrs).empty?
    if expenses = attrs['expenses_attributes']
      expenses.values.each do |expense|
        return true unless (expense.keys - acceptable_expenses_attrs).empty?
      end
    end
    false
  end
end
