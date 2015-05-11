require 'spec_helper'

describe Spree::OrderCapturing do
  describe '#capture_payments' do
    subject { Spree::OrderCapturing.new(order).capture_payments }

    context "eligible payment methods specified" do
      let!(:order) { create(:order, ship_address: create(:address)) }
      let!(:store_credit_payment_method) { create(:store_credit_payment_method, auto_capture: false) }

      let!(:product) { create(:product, price: 10.00) }
      let!(:variant) do
        create(:variant, price: 10, product: product, track_inventory: false, tax_category: tax_rate.tax_category)
      end
      let!(:shipping_method) { create(:free_shipping_method) }
      let(:tax_rate) { create(:tax_rate, amount: 0.1, zone: create(:global_zone, name: "Some Tax Zone")) }

      before do
        allow(Spree::OrderCapturing).to receive(:eligible_payments).and_return(
          [Spree::PaymentMethod::StoreCredit, Spree::Gateway::Bogus]
        )
      
        create(:store_credit, user: order.user, amount: 10)
        order.contents.add(variant, 3)
        order.update!
        @bogus_payment = create(:payment, order: order, amount: order.total)
        order.contents.advance
        @store_credit_payment = order.payments.store_credits.first
        order.complete!
        order.reload
      end

      it "captures store credits first" do
        subject
        expect(@store_credit_payment.capture_events.sum(:amount)).to eq 10.0
        expect(@bogus_payment.capture_events.sum(:amount)).to eq(order.total - 10.0)
      end
    end
  end
end
