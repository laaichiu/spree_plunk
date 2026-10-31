# Transactional Email Inventory

Last updated: 2026-10-31

This document tracks the email ownership boundary between Spree/Rails, `spree_emails`, `spree_plunk`, and Plunk. It is intentionally more detailed than the README so implementation work can move email by email without losing attribution.

## Current Rule

- Spree remains the source of truth for orders, fulfillments, returns, invitations, exports, reports, password reset tokens, newsletter verification tokens, and consent state.
- `spree_plunk` may own a transactional send only when the Spree fact source, recipient, template data, sender domain, idempotency behavior, and fallback behavior are explicit.
- Plunk sends through `POST /v1/send` for direct transactional handoff. Hosted Plunk does not require SMTP for this path.
- Localhost storefront links can be used during local testing, but the `from` email domain must be verified in the Plunk project.
- Do not let two systems send the same email type unless duplicate prevention is built and tested.
- Transactional sends must not subscribe, resubscribe, unsubscribe, or otherwise change marketing consent.
- Inbound Plunk consent writeback is unsubscribe-only: `contact.unsubscribed` can remove the integration store's local newsletter subscription; `contact.subscribed` is ignored because Plunk state cannot prove mailbox ownership or replace Spree confirmation.
- Order, fulfillment, and return transactional template data is sent as non-persistent Plunk data and includes structured values plus Plunk-template-friendly HTML/text fragments for line items, totals, addresses, tracking, and returned items.
- Use [`docs/spree-emails-handoff-checklist.md`](spree-emails-handoff-checklist.md) when evaluating or validating a partial handoff from `spree_emails`.
- A historical 2026-05-31 host-app validation covered the previous Spree event/model names. It does not verify the current canonical `order.placed`, `fulfillment.fulfilled`, and `return.refunded` paths; see the handoff checklist before relying on live delivery.
- Individual trigger probes listed below cover selected paths only; they are not a complete live handoff covering every current trigger, duplicate sender, delivery marker, and Plunk outcome.

## Newsletter Email Identity: Case And Whitespace

Spree's customer and newsletter records normalize email differently. `Spree::Customer` uses `squish` and preserves letter case, while `Spree::NewsletterSubscriber` strips surrounding whitespace and lowercases the address. Spree 6.0.1's Active Record normalizer applies to subscriber assignments and lookup conditions, so the subscribe service's record lookup uses the normalized subscriber address. Customer lookup still preserves letter case because the customer model does not lowercase its stored email.

For `spree_plunk`, leading or trailing whitespace and ASCII letter-case changes should represent the same email identity. They must not create a second Plunk contact, reset marketing consent, or trigger an unsubscribe/resubscribe cycle. A genuinely different email address resets consent and removes that customer's old newsletter subscriber rows. The new address stays unsubscribed until the customer explicitly opts in and completes Spree's confirmation flow.

On a genuine email identity change, `spree_plunk` removes the customer's newsletter subscriber rows from every store, queues an unsubscribe for the previous Plunk address, and upserts the new address as unsubscribed. The private Spree event payload contains no email address; the previous value is handed to the synchronous subscriber through request-local context and then passed only to the unsubscribe job. Case-only and whitespace-only changes do not trigger this cleanup.

Do not use Ruby `String#casecmp?` as proof that two addresses belong to the same mailbox. It applies Unicode case folding, which can equate distinct strings such as the Latin long-s (`ſ`) and ASCII `s`. Spree 6.0.1 still uses `casecmp?` when choosing the customer to associate with a newsletter subscription; a Unicode lookalike can therefore be linked to the signed-in customer even though the addresses are distinct. Its double-opt-in shortcut uses exact equality between the normalized subscriber email and the customer's email, so a casing mismatch can also cause an extra confirmation email. The customer email-change decorator compares trimmed values after ASCII-only downcasing, so Unicode lookalikes remain distinct and trigger the normal consent reset. Regression specs cover ASCII case-only changes, surrounding whitespace, and a Unicode lookalike. Plunk contact state does not establish mailbox ownership or replace Spree's double opt-in verification.

### Upstream Follow-Up

An issue has been submitted to Spree about newsletter email normalization and matching. Spree 6.0.1 normalizes subscriber emails, but its customer-association and confirmation comparisons still have the behaviors described above. When a later supported Spree release changes them, re-check the actual released `Customer`, `NewsletterSubscriber`, and `Newsletter::Subscribe` behavior, then update this integration if its assumptions have changed. In particular, verify surrounding whitespace, ASCII case-only changes, and Unicode lookalikes against consent reset, subscriber cleanup, confirmation ownership, and Plunk contact synchronization.

## Dashboard Template Editing

`spree_core` owns the editable-template registry, persistence, revision workflows, and preview renderer; `spree_api` exposes the editor through the Admin API. `spree_emails` normally registers its customer mailers there, but it is not required for the dashboard editor itself. `spree_plunk` registers twelve customer email keys, including the split-checkout order-group confirmation, with default Liquid views and static preview samples. Seller lifecycle messages use Plunk Template IDs or inline fallback content because Spree 6 does not register those mailers in the editor.

When a store has published a Spree version for the email's locale, `spree_plunk` renders the version through Spree core and sends the resulting subject and HTML through Plunk's inline `POST /v1/send` fields. Drafts do not affect delivery. With no published override, the configured Plunk Template ID or inline presenter body remains the fallback. The shared layout can also be edited in Spree and is applied when a published email template is rendered. Store-owner notification remains operator-facing and uses its Plunk Template ID.

## Customer-Facing Email Matrix

| Email or flow | Spree fact source | Current Spree sender | Current `spree_plunk` status | Recommended owner now | Guardrails |
| --- | --- | --- | --- | --- | --- |
| Password reset | `customer.password_reset_requested` from Store API password reset creation | `Spree::CustomerEmailSubscriber` in `spree_emails` | Implemented through `SpreePlunk::TransactionalEmailSubscriber`, `password_reset` presenter, and `POST /v1/send`; locally received through Plunk and trigger-probe verified with `spree_emails` absent | Choose one sender for Store API reset requests | Keep reset token and reset URL as non-persistent Plunk data. Keep Spree token generation and redirect URL validation as the authority. |
| Newsletter double opt-in confirmation | `newsletter_subscriber.subscription_requested` | `Spree::NewsletterMailer.email_confirmation` from `spree_emails` when consumer transactional emails are enabled | Implemented and trigger-probe verified through `Spree::Newsletter::Subscribe` with `spree_emails` absent | `spree_plunk` when this email type switch is enabled and Spree duplicate sending is controlled | Do not set Plunk `subscribed: true` until Spree verifies the subscriber. Send verification token/URL as non-persistent Plunk data. |
| Manual order confirmation resend | `order.resend_confirmation_email` | `Spree::OrderMailer.confirm_email` or `Spree::OrderGroupMailer.confirm_email` from `spree_emails` when consumer transactional emails are enabled | Implemented; grouped orders route the order action to the purchase-level confirmation | `spree_plunk` when the resend switch is enabled | Shares the matching order or order-group confirmation template and delivery marker. |
| Order confirmation on checkout completion | `order.placed` | `Spree::OrderMailer.confirm_email` from `spree_emails`; also may send store owner notification | Implemented; subscribes to the canonical Spree event and tracks `spree.order.placed` in Plunk | `spree_plunk` when the confirmation switch is enabled | Reads `notify_customer: false` from event metadata and preserves `confirmation_delivered`. Store owner notification has a separate switch and marker. |
| Split-checkout purchase confirmation | `order_group.completed` | `Spree::OrderGroupMailer.confirm_email` from `spree_emails` | Implemented; suppresses child-order receipts and sends one purchase-level confirmation | `spree_plunk` when the order confirmation switch is enabled | Uses the `spree/order_group_mailer/confirm_email` dashboard template and the order-group delivery marker. |
| Order cancellation | `order.canceled` | `Spree::OrderMailer.cancel_email` from `spree_emails` | Implemented and trigger-probe verified through `Spree::Orders::Cancel` with `spree_emails` absent; still tracks `spree.order.canceled` as a Plunk event | `spree_plunk` when the cancellation switch is enabled | Respects `notify_customer: false`. |
| Fulfillment notification | `fulfillment.fulfilled` | `Spree::FulfillmentMailer.fulfilled_email` from `spree_emails` when consumer transactional emails are enabled | Implemented; subscribes to the canonical Spree event and tracks `spree.fulfillment.fulfilled` in Plunk | `spree_plunk` when the fulfillment email switch is enabled | Reads `notify_customer: false` from event metadata and resolves the current `Spree::Fulfillment` record. |
| Return refund notification | `return.refunded` | `Spree::ReturnMailer.refunded_email` from `spree_emails` when consumer transactional emails are enabled | Implemented; subscribes to the canonical Spree event and tracks `spree.return.refunded` in Plunk | `spree_plunk` when the return refund switch is enabled | Resolves the current `Spree::Return` record and skips returns with no amount actually refunded. |
| Digital downloads ready/resend | `order.placed`, `order.resend_digital_links_email` | `Spree::DigitalAssetEmailSubscriber` and `Spree::DigitalAssetMailer` from `spree_emails` | Implemented through the Plunk subscriber and `digital_asset_ready` presenter | `spree_plunk` when enabled and consumer transactional emails are enabled | Uses `Spree::Api::DigitalLinkUrls`; bearer URLs and expiry data are non-persistent in Plunk. |
| Company invitation | `company_invitation.created` | `Spree::CompanyEmailSubscriber` and `Spree::CompanyMailer` from `spree_emails` | Implemented through the Plunk subscriber and `company_invitation` presenter | `spree_plunk` when enabled and consumer transactional emails are enabled | Pending state is checked before enqueue and before send; invitation acceptance URL is non-persistent. |
| Data-request confirmation | `data_request.confirmation_requested` | `Spree::DataRequestConfirmationEmailSubscriber` and `Spree::CustomerMailer` from `spree_emails` | Implemented through the Plunk subscriber and `data_request_confirmation` presenter | `spree_plunk` when enabled and consumer transactional emails are enabled | Requires a confirmable request and its Spree-generated token; the full URL is non-persistent. |
| Data export ready | `data_request.completed` | `Spree::DataRequestEmailSubscriber` and `Spree::CustomerMailer` from `spree_emails` | Implemented through the Plunk subscriber and `data_export_ready` presenter | `spree_plunk` when enabled and consumer transactional emails are enabled | Access requests only; erasure requests are excluded. Uses `Spree::Api::DataRequestUrls`; the signed, expiring URL is non-persistent. |
| Admin payment link | Explicit Admin request; Spree 6.0.1 has no lifecycle event or stock Dashboard action | `Spree::OrderMailer.payment_link_email` from `spree_emails` | Implemented through `POST /api/v3/admin/orders/:order_id/payment_link`; the endpoint queues the Plunk send | `spree_plunk` when enabled and called by an Admin client or host Dashboard extension | Requires normal Admin order-update authorization, an email address, an incomplete non-canceled order, and consumer transactional emails enabled. The order token URL is non-persistent. The stock Dashboard does not call this extension endpoint. |
| Customer registration confirmation or welcome | No confirmed direct transactional event in the current local Spree source | Usually Devise/Confirmable or host-app behavior if enabled | Not covered | Defer until the account confirmation/welcome rule is explicit | Registration alone must not imply marketing consent. |
| Invitation created, accepted, or resent | `invitation.created`, `invitation.accepted`, `invitation.resent` | `Spree::InvitationMailer` from Spree core | Not covered | Keep Spree/Rails first | Not part of `spree_emails`; replacing it needs a core-mailer boundary decision. |

## Admin And System Email Matrix

| Email or flow | Spree fact source | Current Spree sender | Current `spree_plunk` status | Recommended owner now | Guardrails |
| --- | --- | --- | --- | --- | --- |
| Store owner new order notification | Side effect of `order.placed` or `order_group.completed` handling in Spree's order subscribers | `Spree::OrderMailer.store_owner_notification_email` or `Spree::OrderGroupMailer.store_owner_notification_email` from `spree_emails` | Implemented; grouped checkouts notify from the group once | `spree_plunk` when the store-owner notification switch is enabled and a store notification email is configured | This is an operator notification, not a customer receipt. It has a separate owner switch and respects the order or order-group delivery marker. |
| Export completion | Export generation completion | `Spree::ExportMailer.export_done` from Spree core when the export has a user | Not covered | Keep Spree/Rails first | Admin/system mail. Not part of storefront transactional migration. |
| Report completion | Report generation completion | `Spree::ReportMailer.report_done` from Spree core when the report has a user | Not covered | Keep Spree/Rails first | Admin/system mail. Not part of storefront transactional migration. |
| Webhook endpoint disabled | Webhook endpoint auto-disable path | `Spree::WebhookMailer.endpoint_disabled` from Spree core | Not covered | Keep Spree/Rails first | Operational mail. Do not route through marketing workflows. |
| Seller lifecycle notification | `seller.approved`, `seller.suspended`, `seller.rejected` | `Spree::SellerEmailSubscriber` and `Spree::SellerMailer` from `spree_emails` | Implemented through Plunk seller lifecycle presenters and type-specific template settings | `spree_plunk` when the type switch and store seller transactional preference are enabled | Sends to seller team users and contact email; no internal notes or rejection reasons are included. Seller content is not registered in the Spree customer template editor. |

## Marketing And Automation Boundary

| Flow | Fact source | Current `spree_plunk` status | Owner | Guardrails |
| --- | --- | --- | --- | --- |
| Marketing campaigns and newsletters | Plunk contact state mirrored from Spree newsletter consent | Store-scoped contact sync, unsubscribe-only writeback, and profile/address/global-consent fan-out to stores with existing subscriptions are covered | Plunk | Only Spree's explicit opt-in and confirmation flow can set `subscribed: true`; inbound `contact.subscribed` is ignored. An inbound unsubscribe removes only the integration store's subscription and clears global consent only when none remain. |
| Post-purchase, winback, abandoned checkout, discount delivery | `spree.*` events emitted by `spree_plunk` | Event tracking is covered for cart, checkout, coupon, order, fulfillment, and return events | Plunk workflows | Workflows are suitable for marketing automation, but they should not be the only reliability mechanism for receipts or security mail without duplicate and fallback design. |

## Implemented `spree_plunk` Direct-Send Coverage

| Email type | Event | Setting | Operational status |
| --- | --- | --- | --- |
| Password reset | `customer.password_reset_requested` | `preferred_transactional_email_enabled` and `preferred_password_reset_email_enabled` | Implemented; locally received through Plunk with a verified sender domain; trigger-probe verified with `spree_emails` absent. |
| Newsletter double opt-in confirmation | `newsletter_subscriber.subscription_requested` | `preferred_transactional_email_enabled` and `preferred_newsletter_confirmation_email_enabled` | Implemented; trigger-probe verified through `Spree::Newsletter::Subscribe` with `spree_emails` absent. |
| Order confirmation | `order.placed` | `preferred_transactional_email_enabled` and `preferred_order_confirmation_email_enabled` | Implemented; uses current event metadata for `notify_customer`; preserves `confirmation_delivered`; includes non-persistent order line item, totals, addresses, and fulfillment template data. |
| Split-checkout purchase confirmation | `order_group.completed` | `preferred_transactional_email_enabled` and `preferred_order_confirmation_email_enabled` | Implemented; sends one group-level receipt and suppresses the partial child-order receipt; shares the configured Plunk order confirmation template ID. |
| Manual order confirmation resend | `order.resend_confirmation_email` | `preferred_transactional_email_enabled` and `preferred_order_confirmation_resend_email_enabled` | Implemented; grouped orders route to the purchase-level confirmation template and delivered marker. |
| Order cancellation | `order.canceled` | `preferred_transactional_email_enabled` and `preferred_order_cancellation_email_enabled` | Implemented; trigger-probe verified through `Spree::Orders::Cancel`; preserves `notify_customer: false`; includes non-persistent order line item, totals, address, and fulfillment template data. |
| Fulfillment notification | `fulfillment.fulfilled` | `preferred_transactional_email_enabled` and `preferred_fulfillment_fulfilled_email_enabled` | Implemented; uses current `Spree::Fulfillment` fields and event metadata; includes tracking, tracking URL, cost, and fulfillment item data. |
| Return refund notification | `return.refunded` | `preferred_transactional_email_enabled` and `preferred_return_refunded_email_enabled` | Implemented; uses current `Spree::Return` and skips zero-value refunds; includes non-persistent refunded amount and returned-item data. |
| Store owner new-order notification | `order.placed` or `order_group.completed` | `preferred_transactional_email_enabled` and `preferred_store_owner_notification_email_enabled` | Implemented; grouped checkouts send one group-level notification and preserve the matching delivery marker; includes non-persistent purchase line item, totals, addresses, fulfillments, and customer email template data. |
| Digital downloads ready/resend | `order.placed`, `order.resend_digital_links_email` | `preferred_transactional_email_enabled` and `preferred_digital_asset_ready_email_enabled` | Implemented; uses Spree's download URL helper, supports resend, and keeps links transient. |
| Company invitation | `company_invitation.created` | `preferred_transactional_email_enabled` and `preferred_company_invitation_email_enabled` | Implemented; checks pending status before enqueue and before send; keeps acceptance URL transient. |
| Data-request confirmation | `data_request.confirmation_requested` | `preferred_transactional_email_enabled` and `preferred_data_request_confirmation_email_enabled` | Implemented; requires Spree's confirmable state and event token; keeps confirmation URL transient. |
| Data export ready | `data_request.completed` | `preferred_transactional_email_enabled` and `preferred_data_export_ready_email_enabled` | Implemented for downloadable access requests only; uses Spree's signed download URL and keeps it transient. |
| Admin payment link | `POST /api/v3/admin/orders/:order_id/payment_link` | `preferred_transactional_email_enabled` and `preferred_payment_link_email_enabled` | Implemented as an extension API action; no matching event or stock Dashboard action exists in Spree 6.0.1, so an Admin client/host Dashboard plugin must call it. |
| Seller approved/suspended/rejected | `seller.approved`, `seller.suspended`, `seller.rejected` | Type-specific preference and the store's seller transactional email preference | Implemented; sends to seller users and contact email; content uses Plunk Template IDs or inline fallback rather than Spree's customer template editor. |

## Source Files Checked

- `spree/emails/app/subscribers/spree/order_email_subscriber.rb`
- `spree/emails/app/subscribers/spree/newsletter_subscriber_email_subscriber.rb`
- `spree/emails/app/subscribers/spree/fulfillment_email_subscriber.rb`
- `spree/emails/app/subscribers/spree/return_email_subscriber.rb`
- `spree/api/app/controllers/spree/api/v3/store/customer/password_resets_controller.rb`
- `spree/core/app/subscribers/spree/invitation_email_subscriber.rb`
- `spree/core/app/models/spree/export.rb`
- `spree/core/app/models/spree/report.rb`
- `spree/core/app/models/spree/webhook_endpoint.rb`
- `app/subscribers/spree_plunk/transactional_email_subscriber.rb`
- `app/services/spree_plunk/send_transactional_email.rb`
- `lib/spree_plunk/transactional_email_types.rb`
