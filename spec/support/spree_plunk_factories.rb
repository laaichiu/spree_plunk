module SpreePlunkFactoryHelpers
  def create_fulfilled_order(store:, customer: nil, email: nil)
    order = create(:order_with_line_items, store: store, customer: customer, email: email || customer&.email)
    order.fulfillments.each do |fulfillment|
      fulfillment.update_columns(
        status: 'fulfilled',
        fulfilled_at: Time.current,
        tracking: '1234567890'
      )
    end
    order.reload
  end
end

RSpec.configure do |config|
  config.include SpreePlunkFactoryHelpers
end
