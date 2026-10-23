# `spree_emails` Handoff Checklist

Last updated: 2026-10-23

This checklist is for host apps that remove `spree_emails` and expect `spree_plunk` plus hosted Plunk to own customer-facing transactional sends.

## Preflight

Run the handoff inspector from the host app. The command resolves the installed `spree_plunk` gem path through Bundler, so it works for path, git, and packaged gem installs without a machine-specific absolute path:

```sh
bundle exec rails runner 'load Gem.loaded_specs.fetch("spree_plunk").full_gem_path + "/script/inspect_transactional_email_handoff.rb"'
```

Useful selectors:

```sh
STORE_CODE=default bundle exec rails runner 'load Gem.loaded_specs.fetch("spree_plunk").full_gem_path + "/script/inspect_transactional_email_handoff.rb"'
PLUNK_INTEGRATION_ID=1 bundle exec rails runner 'load Gem.loaded_specs.fetch("spree_plunk").full_gem_path + "/script/inspect_transactional_email_handoff.rb"'
```

Expected preflight signals when `spree_emails` has been removed:

- `spree_emails gem loaded: false`
- `Spree::Emails::Engine: missing`
- `Spree::OrderMailer`, `Spree::FulfillmentMailer`, `Spree::ReturnMailer`, and `Spree::NewsletterMailer`: `missing`
- `spree_plunk gem loaded: true`
- `transactional master switch: ON`
- the inspector prints the configured sender domain; verify separately in Plunk that this domain is verified before sending

On Spree 6.0.0.rc5 and later, also open **Settings → Emails → Templates**. `spree_plunk` registers the seven customer email types it sends, Spree's shared layout, and the shared partials those templates render. The editor works while the `spree_emails` engine and mailers are absent. A published Spree override is rendered by Spree and delivered through Plunk's inline send fields. Drafts do not affect delivery. Without a published Spree version, the configured Plunk Template ID is used; if no ID is configured, delivery uses the presenter's inline HTML body.

If `spree_emails` is absent and a row says `none when spree_emails absent`, that email type will not be sent until both the transactional master switch and its `spree_plunk` type switch are enabled.

## Validation Levels

Use these levels to avoid confusing a Plunk send smoke test with full Spree ownership verification.

| Level | What it proves | What it does not prove |
| --- | --- | --- |
| Direct-send smoke test | Plunk credentials, verified sender domain, `/v1/send`, template ID or inline HTML, and recipient delivery are working. | The Spree event/controller path enqueues exactly one `SpreePlunk::SendTransactionalEmailJob`, delivery markers are updated, or no other sender also reacts to the same business action. |
| Handoff preflight | The host app boots without `spree_emails`, `spree_plunk` is loaded, the integration exists, and the expected switches are on. | The customer/admin workflow that should trigger each email type has been exercised end-to-end. |
| Live handoff verification | A real Spree or storefront action triggers the selected email type, Plunk accepts or delivers it, and no duplicate sender is observed for that action. | Future regressions; keep specs and a short manual smoke path for release checks. |

If all `spree_plunk` email switches are already enabled, do not toggle them one by one just for validation. Leave the desired production-like configuration in place and trigger each email type through its normal workflow once. Toggle one email type at a time only when isolating a failure or duplicate.

## Duplicate Checks

Receiving one email in the test inbox is a useful signal, but it is not the whole duplicate check. For each live trigger, collect these signals together:

- the inbox receives one matching email for the test recipient and trigger window
- Sidekiq shows one successful `SpreePlunk::SendTransactionalEmailJob` for the email type/resource
- Plunk logs show one accepted or delivered transactional send for the same recipient/template/time window
- Rails logs do not show a fallback `ActionMailer` delivery for the matching `spree_emails` mailer
- no Plunk workflow, campaign, or automation is also configured to send the same operational email from the same event
- applicable Spree markers move once, such as `confirmation_delivered` or `store_owner_notification_delivered`

When `spree_emails` has been removed, duplicates from `Spree::OrderMailer`, `Spree::FulfillmentMailer`, `Spree::ReturnMailer`, and `Spree::NewsletterMailer` should be impossible because those constants are missing. Duplicates can still happen from another host-app mailer, a queued old job, a Plunk workflow that sends the same message, or triggering the same action twice.

## Automated Validation

The RSpec suite covers the Spree 6 event names, presenters, job idempotency, preference migrations, and rendering previews for all seven registered customer email templates. It verifies the Plunk HTTP request with stubs; it does not verify live Plunk delivery or replace the host-app checks in **Live Verification Steps**.

## Handoff Matrix

| Email type | Trigger | Current `spree_plunk` capability | Required switch | Expected success signal | Duplicate guard |
| --- | --- | --- | --- | --- | --- |
| Password reset | Store API customer password reset request | Implemented | `password_reset_email_enabled` | Plunk delivery contains reset URL/token as non-persistent data | No bundled `spree_emails` Store API reset mailer in current local Spree source |
| Newsletter confirmation | Newsletter subscription request | Implemented | `newsletter_confirmation_email_enabled` | Plunk delivery contains verification URL/token as non-persistent data | Disable any other newsletter confirmation sender |
| Order confirmation | Checkout completion with `notify_customer: true` | Implemented | `order_confirmation_email_enabled` | Plunk delivery accepted and order `confirmation_delivered` becomes true | Skips when `notify_customer: false` or already delivered |
| Split-checkout confirmation | `order_group.completed` with `notify_customer: true` | Implemented | `order_confirmation_email_enabled` | Plunk delivery accepted and order group `confirmation_delivered` becomes true | Sends one purchase-level confirmation and suppresses child-order confirmations |
| Order confirmation resend | Admin order or order-group resend action | Implemented | `order_confirmation_resend_email_enabled` | Plunk delivery accepted and order or order group `confirmation_delivered` becomes true | Shares the corresponding order/order-group delivered marker |
| Order cancellation | Order cancellation with customer notification enabled | Implemented | `order_cancellation_email_enabled` | Plunk delivery contains order line items, totals, addresses, and fulfillments | Skips when `notify_customer: false` |
| Fulfillment notification | `fulfillment.fulfilled` event | Implemented | `fulfillment_fulfilled_email_enabled` | Plunk delivery contains tracking and fulfillment item details | Choose one sender when `spree_emails` is present |
| Return refund | `return.refunded` event | Implemented | `return_refunded_email_enabled` | Plunk delivery contains refunded amount and returned-item details | Choose one sender when `spree_emails` is present |
| Store owner notification | Order or order-group completion when store has `new_order_notifications_email` | Implemented | `store_owner_notification_email_enabled` | Plunk delivery accepted and order or order group `store_owner_notification_delivered` becomes true | Skips when already delivered |

## Live Verification Steps

1. Confirm the host app boots without `spree_emails`.
2. Confirm the Plunk integration can connect and uses a verified sender domain.
3. Run the handoff inspector and save the output with the test notes.
4. Confirm the intended `spree_plunk` email switches are enabled.
5. Trigger each enabled email type from its normal Spree or storefront workflow.
6. Watch Sidekiq for `SpreePlunk::SendTransactionalEmailJob`.
7. Confirm Plunk delivery or failure logs for the matching recipient and email type.
8. Confirm Spree state markers when applicable:
   - `confirmation_delivered` for order confirmation and resend on the order or order group
   - `store_owner_notification_delivered` for store owner notification on the order or order group
9. Confirm no `spree_emails` mailer constant is present and no duplicate sender is observed using the duplicate checks above.
10. Disable or leave off any email type that has not passed live verification.

## Known Boundaries

`spree_plunk` does not currently replace these Spree/Rails-owned mailers:

- customer registration confirmation or welcome mail, because the current local Spree source has no explicit `spree_plunk` event boundary for it
- invitations from `Spree::InvitationMailer`
- export completion from `Spree::ExportMailer`
- report completion from `Spree::ReportMailer`
- webhook endpoint disabled notifications from `Spree::WebhookMailer`
- Admin payment-link emails; Spree currently has no event trigger this extension can subscribe to.

These are outside `spree_emails` storefront transactional replacement. Replacing them needs separate ownership, recipient, template data, and failure-behavior decisions.
