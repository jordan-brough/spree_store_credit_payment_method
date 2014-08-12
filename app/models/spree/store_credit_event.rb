module Spree
  class StoreCreditEvent < ActiveRecord::Base
    acts_as_paranoid

    belongs_to :store_credit
    belongs_to :originator, polymorphic: true

    scope :exposed_events, -> { where.not(action: [Spree::StoreCredit::ELIGIBLE_ACTION, Spree::StoreCredit::AUTHORIZE_ACTION]) }
    scope :reverse_chronological, -> { order(created_at: :desc) }

    delegate :currency, to: :store_credit

    def display_amount
      Spree::Money.new(amount, { currency: currency })
    end

    def display_user_total_amount
      Spree::Money.new(user_total_amount, { currency: currency })
    end

    def display_event_date
      I18n.l(created_at, format: :date_slash)
    end

    def display_action
      case action
      when Spree::StoreCredit::CAPTURE_ACTION
        Spree.t('store_credits.captured')
      when Spree::StoreCredit::AUTHORIZE_ACTION
        Spree.t('store_credits.authorized')
      when Spree::StoreCredit::ALLOCATION_ACTION
        Spree.t('store_credits.allocated')
      when Spree::StoreCredit::VOID_ACTION, Spree::StoreCredit::CREDIT_ACTION
        Spree.t('store_credits.credit')
      end
    end

    def order
      Spree::Payment.find_by_response_code(authorization_code).try(:order)
    end
  end
end
