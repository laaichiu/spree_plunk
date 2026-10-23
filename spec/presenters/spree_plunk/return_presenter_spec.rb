require 'spec_helper'

RSpec.describe SpreePlunk::ReturnPresenter do
  it 'builds refund payload details for the current return model' do
    store = create(:store, code: 'default-store')
    return_record = create(:return, store: store)

    payload = described_class.new(return_record: return_record, store: store).call

    expect(payload).to include(
      return_number: return_record.number,
      return_status: return_record.status,
      refund_total: return_record.refund_total.to_f,
      refunded_total: return_record.refunded_total.to_f,
      refundable_total: return_record.refundable_total.to_f,
      order_number: return_record.order.number,
      return_items_count: return_record.return_line_items.size,
      store_code: 'default-store'
    )
    expect(payload.keys).not_to include(:reimbursement_id, :reimbursement_number, :reimbursement_status, :paid_amount, :unpaid_amount)
  end
end
