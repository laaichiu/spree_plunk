Spree::Core::Engine.add_routes do
  post '/plunk/webhooks/unsubscribe/:integration_id',
       to: 'plunk/unsubscribe_webhooks#create',
       as: :plunk_unsubscribe_webhook

  post '/api/v3/admin/orders/:order_id/payment_link',
       to: 'api/v3/admin/orders/payment_links#create',
       as: :admin_order_payment_link
end
