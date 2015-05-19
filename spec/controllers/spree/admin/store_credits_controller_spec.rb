require 'spec_helper'

shared_examples "category loader" do
  it "sets the credit_categories variable to a list of categories sorted by category name " do
    expect(assigns(:credit_categories)).to eq [a_credit_category, b_credit_category]
  end
end

describe Spree::Admin::StoreCreditsController do
  stub_authorization!
  let(:user) { create(:user) }
  let(:admin_user) { create(:admin_user) }

  let!(:b_credit_category) { create(:store_credit_category, name: "B category") }
  let!(:a_credit_category) { create(:store_credit_category, name: "A category") }

  describe "GET index" do

    before { spree_get :index, user_id: user.id }

    context "the user does not have any store credits" do
      it "sets the store_credits variable to an empty list" do
        expect(assigns(:store_credits)).to be_empty
      end
    end

    context "the user has store credits" do
      let(:store_credit) { create(:store_credit, user: user) }

      it "sets the store_credits variable to a list containing the store credits" do
        expect(assigns(:store_credits)).to eq [store_credit]
      end
    end
  end

  describe "GET new" do
    let!(:store_credit)      { create(:store_credit, category: a_credit_category) }

    before { spree_get :new, user_id: user.id }

    it_behaves_like "category loader"

    it "sets the store_credit variable to a new store credit model" do
      expect(assigns(:store_credit)).not_to be_persisted
    end
  end

  describe "POST create" do
    subject { spree_post :create, parameters }

    before  {
      allow(controller).to receive_messages(try_spree_current_user: admin_user)
      create(:primary_credit_type)
    }

    context "the passed parameters are valid" do
      let(:parameters) do
        {
          user_id: user.id,
          store_credit: {
            amount: 1.00,
            category_id: a_credit_category.id
          }
        }
      end

      it "redirects to index" do
        expect(subject).to redirect_to spree.admin_user_store_credits_path(user)
      end

      it "creates a new store credit" do
        expect { subject }.to change(Spree::StoreCredit, :count).by(1)
      end

      it "associates the store credit with the user" do
        subject
        expect(user.reload.store_credits.count).to eq 1
      end

      it "assigns the store credit's created by to the current user" do
        subject
        expect(user.reload.store_credits.first.created_by).to eq admin_user
      end

      it 'sets the admin as the store credit event originator' do
        expect { subject }.to change { Spree::StoreCreditEvent.count }.by(1)
        expect(Spree::StoreCreditEvent.last.originator).to eq admin_user
      end
    end

    context "the passed parameters are invalid" do
      let(:parameters) do
        {
          user_id: user.id,
          store_credit: {
            amount: -1.00,
            category_id: a_credit_category.id
          }
        }
      end

      before { subject }

      it "renders the new action" do
        expect(response).to render_template :new
      end

      it_behaves_like "category loader"
    end
  end

  describe "GET edit" do
    let!(:store_credit)      { create(:store_credit, category: a_credit_category) }

    before { spree_get :edit, user_id: user.id, id: store_credit.id }

    it_behaves_like "category loader"

    it "sets the store_credit variable to the persisted store credit" do
      expect(assigns(:store_credit)).to eq store_credit
    end
  end

  describe "PUT update" do
    let!(:store_credit) { create(:store_credit, user: user, category: b_credit_category) }

    subject { spree_put :update, parameters }

    before  { allow(controller).to receive_messages(try_spree_current_user: admin_user) }

    context "the passed parameters are valid" do
      let(:updated_amount) { 300.0 }

      let(:parameters) do
        {
          user_id: user.id,
          id: store_credit.id,
          store_credit: {
            amount: updated_amount,
            category_id: a_credit_category.id
          }
        }
      end

      context "the store credit has been partially used" do
        before { store_credit.update_attributes(amount_used: 10.0) }

        context "the new amount is greater than the used amount" do
          let(:updated_amount) { 11.0 }
          it "updates the amount to be the passed in amount" do
            subject
            expect(store_credit.reload.amount).to eq updated_amount
          end
        end

        context "the new amount is less than the used amount" do
          let(:updated_amount) { 9.0 }
          it "does not update the amount" do
            expect { subject }.not_to change { store_credit.reload.amount }
          end

          it "responds with an error message" do
            subject
            expect(flash.now[:error]).to match "Unable to update"
            expect(flash.now[:error]).to match "greater than the credited amount"
          end
        end
      end

      context "the store credit has not been used" do
        it "redirects to index" do
          expect(subject).to redirect_to spree.admin_user_store_credits_path(user)
        end

        it "does not create a new store credit" do
          expect { subject }.to_not change(Spree::StoreCredit, :count)
        end

        it "assigns the store credit's created by to the current user" do
          subject
          expect(store_credit.reload.created_by).to eq admin_user
        end

        it "updates passed amount" do
          subject
          expect(store_credit.reload.amount).to eq updated_amount
        end

        it "updates passed category" do
          subject
          expect(store_credit.reload.category).to eq a_credit_category
        end

        it "maintains the user association" do
          subject
          expect(store_credit.reload.user).to eq user
        end
      end
    end

    context "the passed parameters are invalid" do
      let(:parameters) do
        {
          user_id: user.id,
          id: store_credit.id,
          store_credit: {
            amount: -1.00,
            category_id: a_credit_category.id
          }
        }
      end

      before { subject }

      it "renders the edit action" do
        expect(response).to render_template :edit
      end

      it_behaves_like "category loader"
    end
  end

  describe "PUT invalidate" do
    let!(:store_credit) { create(:store_credit, user: user, category: b_credit_category) }

    it "attempts to invalidate the store credit" do
      expect { spree_put :invalidate, user_id: user.id, id: store_credit.id }.to change { store_credit.reload.invalidated_at }.from(nil)
    end

    context "the invalidation is unsuccessful" do
      before do
        store_credit.authorize(5.0, "USD")
        subject
      end

      subject { spree_put :invalidate, user_id: user.id, id: store_credit.id }

      it "returns a 422" do
        expect(response.status).to eq 422
      end

      it "returns an error message" do
        expect(response.body).to match /uncaptured authorization/
      end
    end

    context "html request" do
      subject { spree_put :invalidate, user_id: user.id, id: store_credit.id }

      it "redirects to index" do
        expect(subject).to redirect_to spree.admin_user_store_credits_path(user)
      end
    end

    context "js request" do
      subject { spree_put :invalidate, user_id: user.id, id: store_credit.id, format: :js }

      it "returns a 200 status code" do
        subject
        expect(response.code).to eq "200"
      end
    end
  end
end
