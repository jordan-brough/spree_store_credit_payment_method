module SpreeStoreCredits::OrderDecorator
  extend ActiveSupport::Concern

  included do
    Spree::Order.state_machine.before_transition to: :confirm, do: :add_store_credit_payments
    Spree::Order.state_machine.after_transition to: :complete, do: :send_gift_card_emails

    has_many :gift_cards, through: :line_items

    prepend(InstanceMethods)
  end

  module InstanceMethods
    def finalize!
      create_gift_cards
      super
    end

    def create_gift_cards
      line_items.each do |item|
        item.quantity.times do
          Spree::VirtualGiftCard.create!(amount: item.price, currency: item.currency, purchaser: user, line_item: item) if item.gift_card?
        end
      end
    end

    def send_gift_card_emails
      gift_cards.each do |gift_card|
        Spree::GiftCardMailer.gift_card_email(gift_card).deliver
      end
    end

    def add_store_credit_payments
      payments.store_credits.where(state: 'checkout').map(&:invalidate!)

      # this can happen when auto capture is off and a user tries to complete an
      # order and the store credit gets authorized (but not captured) and the
      # credit card fails.
      authorized_total = payments.store_credits.pending.sum(:amount)

      remaining_total = outstanding_balance - authorized_total

      if user && user.store_credits.any?
        payment_method = Spree::PaymentMethod.find_by_type('Spree::PaymentMethod::StoreCredit')
        raise "Store credit payment method could not be found" unless payment_method

        user.store_credits.order_by_priority.each do |credit|
          break if remaining_total.zero?
          next if credit.amount_remaining.zero?

          amount_to_take = store_credit_amount(credit, remaining_total)
          create_store_credit_payment(payment_method, credit, amount_to_take)
          remaining_total -= amount_to_take
        end
      end

      reconcile_with_credit_card(existing_credit_card_payment, remaining_total)

      if pending_payments.sum(&:amount) != total
        errors.add(:base, Spree.t("store_credit.errors.unable_to_fund")) and return false
      end
    end

    def covered_by_store_credit?
      return false unless user
      user.total_available_store_credit >= total
    end
    alias_method :covered_by_store_credit, :covered_by_store_credit?

    def total_available_store_credit
      return 0.0 unless user
      user.total_available_store_credit
    end

    def order_total_after_store_credit
      total - total_applicable_store_credit
    end

    def total_applicable_store_credit
      if confirm? || complete?
        payments.store_credits.valid.sum(:amount)
      else
        [total, (user.try(:total_available_store_credit) || 0.0)].min
      end
    end

    def display_total_applicable_store_credit
      Spree::Money.new(-total_applicable_store_credit, { currency: currency })
    end

    def display_order_total_after_store_credit
      Spree::Money.new(order_total_after_store_credit, { currency: currency })
    end

    def display_total_available_store_credit
      Spree::Money.new(total_available_store_credit, { currency: currency })
    end

    def display_store_credit_remaining_after_capture
      Spree::Money.new(total_available_store_credit - total_applicable_store_credit, { currency: currency })
    end

    private

    def after_cancel
      super

      # Free up authorized store credits
      payments.store_credits.pending.each { |payment| payment.void_transaction! }

      # payment_state has to be updated because after_cancel on
      # super does an update_column on the payment_state to set
      # it to 'credit_owed' but that is not correct if the
      # payments are captured store credits that get totally refunded

      reload
      updater.update_payment_state
      updater.persist_totals
    end

    def existing_credit_card_payment
      other_payments = payments.valid.not_store_credits
      raise "Found #{other_payments.size} payments and only expected 1" if other_payments.size > 1
      other_payments.first
    end

    def reconcile_with_credit_card(other_payment, amount)
      return unless other_payment

      unless other_payment.source.is_a?(Spree::CreditCard)
        raise "Found unexpected payment method. Credit cards are the only other supported payment type"
      end

      if amount.zero?
        other_payment.invalidate!
      else
        other_payment.update_attributes!(amount: amount)
      end

      payments.reload
    end

    def create_store_credit_payment(payment_method, credit, amount)
      payments.create!(source: credit,
                       payment_method: payment_method,
                       amount: amount,
                       state: 'checkout',
                       response_code: credit.generate_authorization_code)
    end

    def store_credit_amount(credit, total)
      [credit.amount_remaining, total].min
    end
  end
end

Spree::Order.include SpreeStoreCredits::OrderDecorator
