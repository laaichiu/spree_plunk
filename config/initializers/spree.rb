Rails.application.config.after_initialize do
  Spree.integrations << 'Spree::Integrations::Plunk'
  Spree::Cart.publishes_events(
    'checkout.email_entered',
    'checkout.step_viewed',
    'checkout.step_completed',
    'coupon.entered',
    'coupon.removed',
    'coupon.applied',
    'coupon.denied'
  )
  Spree.subscribers << SpreePlunk::CartSubscriber
  Spree.subscribers << SpreePlunk::ContactSubscriber
  Spree.subscribers << SpreePlunk::NewsletterSubscriber
  Spree.subscribers << SpreePlunk::StorefrontOrderSubscriber
  Spree.subscribers << SpreePlunk::OrderSubscriber
  Spree.subscribers << SpreePlunk::FulfillmentSubscriber
  Spree.subscribers << SpreePlunk::ReturnSubscriber
  Spree.subscribers << SpreePlunk::TransactionalEmailSubscriber
end
