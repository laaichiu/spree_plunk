# Spree Plunk

`spree_plunk` is a Spree Commerce extension that connects a Spree store to Plunk for server-side contact sync, consent-safe event tracking, and selected transactional email handoff.

It is built for marketing use cases such as workflows, campaigns, and audience segmentation. Transactional emails still stay with Spree/Rails by default unless an operator explicitly enables the Plunk transactional email master switch and one of the supported email-type switches.

`spree_plunk` currently targets Spree 6.0.0.rc5 or later. Spree 6 core provides the editable email-template registry, Admin API, renderer, and preview workflow used here.

## What This Extension Does

- syncs Spree customers and newsletter subscribers into Plunk contacts
- refreshes Plunk contact data when customer or address records change
- tracks selected Spree commerce events into Plunk for workflows and segmentation
- keeps marketing consent explicit instead of inferring it from behavioral events
- supports both hosted Plunk and self-hosted Plunk through a configurable base API URL
- can optionally accept authenticated Plunk unsubscribe callbacks; subscribe callbacks never bypass Spree confirmation
- can optionally send the first supported transactional email types through Plunk's HTTP send API

## Current Features

### Contact Sync

The extension currently syncs contact state from these Spree-side sources:

- customer created
- customer updated
- address created
- address updated
- newsletter subscriber created
- newsletter subscriber verified
- newsletter subscriber deleted

The contact payload can include:

- `email`
- `subscribed`
- `external_user_id`
- `store_code`
- `first_name`
- `last_name`
- `phone`
- `accepts_email_marketing`
- `city`
- `region`
- `country`
- `zip`
- `order_count`
- `last_order_number`
- `last_order_total`

### Event Tracking

The extension currently sends these namespaced events to Plunk:

- `spree.newsletter.subscribed`
- `spree.newsletter.unsubscribed`
- `spree.checkout.email_entered`
- `spree.cart.added`
- `spree.cart.removed`
- `spree.coupon.entered`
- `spree.coupon.removed`
- `spree.coupon.applied`
- `spree.coupon.denied`
- `spree.checkout.step_viewed`
- `spree.checkout.step_completed`
- `spree.order.placed`
- `spree.order.canceled`
- `spree.fulfillment.fulfilled`
- `spree.return.refunded`

These events are intended for:

- workflow triggers
- segmentation
- lifecycle automation
- post-purchase marketing flows

Current storefront event-source boundary:

- cart events are line-item backed so the payload stays item-specific
- checkout events are checkout-service backed so step/email tracking follows real server-side state changes
- coupon events are coupon-handler backed so apply/remove outcomes do not depend on storefront analytics
- the storefront analytics handler is currently unused for the supported event set, which avoids duplicate tracking if Spree later emits overlapping analytics events
- browse-only analytics such as product view, product list view, and product search remain deferred

### Transactional Email Handoff

Transactional email delivery through Plunk is default-off and uses Plunk's HTTP `POST /v1/send` API. It does not use SMTP, so local development can send through hosted Plunk as long as the app can reach Plunk and the sender domain is verified in the Plunk project.

The current direct-send handoff supports:

- Store API password reset emails from `customer.password_reset_requested`
- newsletter double opt-in emails from `newsletter_subscriber.subscription_requested`
- checkout-completion confirmations from `order.placed` and, for a checkout split across multiple orders, `order_group.completed`
- explicit admin order or order-group confirmation resends from `order.resend_confirmation_email`
- order cancellation emails from `order.canceled`
- fulfillment notifications from `fulfillment.fulfilled`
- return refund notifications from `return.refunded`
- store owner new-order notifications from `order.placed` and `order_group.completed`

Current ownership boundary:

- `spree_plunk` owns only the explicitly enabled email types above.
- Admin payment-link emails remain with Spree; this extension has no Spree 6 trigger for them.
- Spree/Rails still owns invitation emails, reports, webhooks, exports, and any other extension-provided mailers that are not listed above.
- Any email type that is also sent by `spree_emails` can duplicate if both systems are configured to send it. Keep one owner per email type while this handoff is partial.
- Password reset is a good early Plunk owner because the local Spree source emits `customer.password_reset_requested`, but the standard consumer email subscriber set does not include a bundled password reset subscriber.
- Order placement reads `notify_customer: false` from event metadata, routes split checkouts through the order-group confirmation, and preserves the order/order-group `confirmation_delivered` guards.
- Reset and verification tokens are sent to Plunk as non-persistent template data.
- Storefront URLs may be local during testing, but the sender email domain must still be verified in Plunk.
- A historical host-app validation on 2026-05-31 covered the earlier Spree event/model names. A complete live handoff across the current canonical Spree 6 triggers has not been verified; use the handoff checklist before relying on production delivery.

See [docs/transactional-email-inventory.md](docs/transactional-email-inventory.md) for the detailed email attribution matrix.

### Spree Dashboard Email Templates

On Spree 6.0.0.rc5 and later, `spree_plunk` registers its customer-facing email templates with Spree core. They appear under **Settings → Emails → Templates** without installing `spree_emails`:

- password reset and newsletter confirmation
- order confirmation and resend (including split-checkout order groups), and order cancellation
- fulfilled delivery and return refund
- the shared Spree email layout

The editor keeps drafts and only changes delivery after **Publish**. A published Spree template for the store and locale is rendered by Spree and sent through Plunk's inline `POST /v1/send` fields. Until then, the configured Plunk Template ID (or the integration's inline fallback) continues to send. This lets Spree's dashboard own the merchant edit flow while Plunk remains the delivery provider. The store owner notification remains a Plunk Template ID because it is an operator email, not a customer email.

Remove `spree_emails` when using `spree_plunk` as its replacement. Installing both can register the same dashboard keys and, more importantly, leave Spree's Action Mailer subscribers able to send duplicate customer emails.

### Admin And Operations

- Spree Admin Plunk integration preferences for credentials and base URL
- connectivity check against the Plunk API
- optional default sender fields for direct transactional sends
- optional public API key storage, intentionally unused by the current server-side MVP
- default-off direct transactional send settings for the supported email handoff
- optional inbound unsubscribe webhook guarded by a bearer token
- replay protection for webhook deliveries with a unique event or execution ID
- retry/discard classification for async sync failures
- stable `Idempotency-Key` values for transactional-email job retries; if Plunk reports a reused key after an ambiguous response, the job stops retrying and records the original HTTP status for delivery reconciliation
- structured error reporting through `Rails.error.report`

## Installation

1. Add this extension to your Gemfile with this line:

    ```ruby
    gem 'spree_plunk', github: 'laaichiu/spree_plunk'
    ```

2. Run the install generator

    ```ruby
    bundle exec rails g spree_plunk:install
    ```

After installation:

1. Open Spree Admin.
2. Create or edit the Plunk integration for the target store.
3. Add the Plunk base URL and secret API key.
4. Verify contact sync and event tracking in a non-production environment first.

When upgrading from a version that used `shipment` or `reimbursement` naming, rerun the install generator so it installs and runs the preference migration. It renames saved fulfillment/return email switches and Plunk template IDs. Update any Plunk templates and workflows separately: their event names and variables are owned by your Plunk project and are not rewritten by this gem.

## Spree Admin Configuration

The Spree Admin **Plunk integration settings** expose these preferences.

| Field | Required | What to enter | Notes |
| --- | --- | --- | --- |
| `Plunk Base URL` | Yes | The Plunk API base URL, such as `https://next-api.useplunk.com` or your self-hosted API base like `https://plunk.example.com/api` | Use the API base only. Do not paste `/contacts`, `/events/track`, or `/v1/track`. |
| `Secret API Key` | Yes | A Plunk secret server key for the workspace, typically `sk_*` | The server-side integration uses this for contact upsert, unsubscribe, event tracking, and direct transactional sends. |
| `Public API Key` | No | An optional browser/public key, typically `pk_*` | Stored only for future use. The current server-side MVP does not use it. |
| `Default Sender Email` | No | A mailbox on a Plunk-verified sending domain, such as `hello@shop.example.com` | Used by direct transactional sends. If blank, the extension falls back to the store `mail_from_address`. |
| `Default Sender Name` | No | A display name such as `Example Store` | Used with `Default Sender Email`. If you set this, also set `Default Sender Email` so the stored sender identity is complete. |
| `Enable Plunk Transactional Email` | No | Check this only after the sender domain is verified in Plunk | Master switch for direct `POST /v1/send` delivery. Disabled by default. |
| `Send Password Reset Emails` | No | Check this when Plunk should send Store API password reset emails | Requires `Enable Plunk Transactional Email`. |
| `Password Reset Template ID` | No | A Plunk template ID for password reset email content | If blank, the extension sends a simple inline HTML body. |
| `Send Newsletter Confirmation Emails` | No | Check this when Plunk should send newsletter double opt-in emails | Requires `Enable Plunk Transactional Email`. Avoid enabling a second Spree/Rails owner for the same email. |
| `Newsletter Confirmation Template ID` | No | A Plunk template ID for newsletter confirmation content | If blank, the extension sends a simple inline HTML body. |
| `Send Order Confirmation Emails` | No | Check this when Plunk should send checkout-completion order confirmation emails | Requires `Enable Plunk Transactional Email`. Respects `notify_customer: false` and `confirmation_delivered`. |
| `Send Order Confirmation Resends` | No | Check this when Plunk should send explicit order confirmation resend requests | Requires `Enable Plunk Transactional Email`. Shares the order confirmation template. |
| `Order Confirmation Template ID` | No | A Plunk template ID for order confirmation content | If blank, the extension sends a simple inline HTML body. |
| `Send Order Cancellation Emails` | No | Check this when Plunk should send customer order cancellation emails | Requires `Enable Plunk Transactional Email`. Respects `notify_customer: false`. |
| `Order Cancellation Template ID` | No | A Plunk template ID for order cancellation content | If blank, the extension sends a simple inline HTML body. |
| `Send Fulfillment Emails` | No | Check this when Plunk should send fulfillment notifications | Requires `Enable Plunk Transactional Email`. |
| `Fulfillment Template ID` | No | A Plunk template ID for fulfillment notification content | If blank, the extension sends a simple inline HTML body. |
| `Send Return Refund Emails` | No | Check this when Plunk should send return refund notifications | Requires `Enable Plunk Transactional Email`. |
| `Return Refund Template ID` | No | A Plunk template ID for return refund notification content | If blank, the extension sends a simple inline HTML body. |
| `Send Store Owner Notifications` | No | Check this when Plunk should send new-order notifications to the store owner address | Requires `Enable Plunk Transactional Email`. Respects `store_owner_notification_delivered`. |
| `Store Owner Notification Template ID` | No | A Plunk template ID for store owner new-order notification content | If blank, the extension sends a simple inline HTML body. |
| `Enable Unsubscribe Webhook` | No | Check this only if Plunk unsubscribe events should remove this store's local Spree newsletter subscription | Disabled by default. `contact.subscribed` callbacks are acknowledged without changing Spree consent. |
| `Unsubscribe Webhook Authorization Token` | Required only when webhook is enabled | A shared secret that you generate yourself | Plunk will send this back in the `Authorization` header as `Bearer <token>`. |

For customer emails, a published Spree dashboard template takes precedence over the Plunk Template ID. If there is no published Spree version, the extension uses the configured Plunk template; if neither exists, it sends the presenter's inline HTML body.

### Where Each Value Comes From

#### Plunk Base URL

- Hosted Plunk uses `https://next-api.useplunk.com`.
- Self-hosted Plunk should use the API base URL that serves endpoints like `/contacts` and `/events/track`.
- Do not paste a full endpoint path into the field.

#### Secret API Key

- Use a secret server key from the target Plunk workspace.
- The current extension talks to `POST /contacts`, `POST /events/track`, and (when enabled) `POST /v1/send`, so it needs the secret key, not the public key.
- A public `pk_*` key will fail the connection check.

#### Public API Key

- Leave this blank unless you are preparing a later browser-side or storefront integration.
- Storing the value here does not enable client-side tracking by itself.

#### Default Sender Email and Name

- Direct transactional sends use `Default Sender Email` first and fall back to the store `mail_from_address`.
- Hosted Plunk validates the domain of the `from` email address. Verifying `shop.example.com` allows addresses such as `hello@shop.example.com`, but not `hello@example.com`.
- These fields do not affect contact sync, newsletter sync, or event tracking.
- They are safe to leave blank if transactional email handoff is disabled.

#### Transactional Email Settings

- `Enable Plunk Transactional Email` is the master switch.
- Each supported email type has its own opt-in switch.
- Template IDs are optional. When a template ID is present, Plunk renders the template with the provided `data` payload. When it is blank, the extension sends a simple inline HTML body.
- Password reset payloads include `reset_token` and `reset_url` as non-persistent Plunk data.
- Newsletter confirmation payloads include `verification_token`, `verification_url`, and `confirmation_url` as non-persistent Plunk data.
- Order confirmation, cancellation, and store owner notification payloads include non-persistent order template data such as order number, customer identity, line item fragments, totals, addresses, fulfillment summaries, completion time, cancellation time, and store URL.
- Fulfillment payloads include non-persistent tracking, delivery method, cost, fulfilled time, item fragments, and store URL.
- Return payloads include non-persistent return number, status, refunded amount, returned item fragments, and store URL.
- Localhost storefront URLs are acceptable in test links, but the sender email domain must be verified in Plunk even for local testing.

## Recommended Setup Flow

1. In Plunk, confirm that you have a usable secret API key for the correct workspace.
2. In Spree Admin, set `Plunk Base URL` and `Secret API Key`.
3. Run the built-in connection check from the admin UI.
4. Create or update a newsletter subscriber in Spree and confirm that a Plunk contact is created.
5. Complete a test order and confirm that Plunk receives `spree.order.placed`.
6. Enable the inbound unsubscribe webhook only after the outbound contact sync path is already behaving correctly.

### Transactional Email Setup Flow

1. In Plunk, verify the sender domain you plan to use.
2. In Spree Admin, set `Default Sender Email` to a mailbox on that verified domain, or make sure the store `mail_from_address` already uses one.
3. Enable `Enable Plunk Transactional Email`.
4. Enable exactly the email types that Plunk should own.
5. For customer emails, either publish a Spree dashboard template or add the matching Plunk template ID as a fallback; with neither configured, the extension sends its inline HTML body.
6. Trigger the selected email type, such as password reset, newsletter subscription request, order placement, order cancellation, fulfillment, return refund, or explicit order confirmation resend.
7. Watch Sidekiq and Plunk delivery logs for send failures such as unverified sender domains.

Copy-ready Plunk template HTML lives in [`plunk_templates/`](plunk_templates/). These files are examples to copy into Plunk; the gem does not import, create, or synchronize Plunk templates. The directory includes Transactional templates for the Plunk Template ID fallback fields and a Marketing campaign example.

To inspect a host app after removing `spree_emails`, run:

```sh
bundle exec rails runner 'load Gem.loaded_specs.fetch("spree_plunk").full_gem_path + "/script/inspect_transactional_email_handoff.rb"'
```

The detailed `spree_emails` removal handoff checklist lives in [`docs/spree-emails-handoff-checklist.md`](docs/spree-emails-handoff-checklist.md).
Use it to distinguish Plunk direct-send smoke tests from full live handoff verification through real Spree triggers and duplicate checks.

### Plunk Template Variables For Order Emails

Order-backed transactional emails expose top-level Plunk variables. Use `{{order_number}}`, not `{{data.order_number}}`, in hosted Plunk templates.

Useful variables include:

- `{{store_name}}`, `{{store_code}}`, `{{store_url}}`
- `{{recipient_email}}`, `{{customer_email}}`, `{{customer_name}}`, `{{customer_first_name}}`, `{{customer_last_name}}`
- `{{order_number}}`, `{{status}}`, `{{payment_status}}`, `{{fulfillment_status}}`, `{{completed_at}}`, `{{canceled_at}}`
- `{{order_total}}`, `{{item_total_display}}`, `{{delivery_total_display}}`, `{{tax_total_display}}`, `{{discount_total_display}}`
- `{{line_items_html}}` or `{{line_items_text}}`
- `{{totals_html}}` or `{{totals_text}}`
- `{{shipping_address_text}}`, `{{billing_address_text}}`
- `{{fulfillments_html}}` or `{{fulfillments_text}}`

The copy-ready templates use pre-rendered HTML fragments for predictable email markup and simpler Plunk templates. The same payload also includes structured `line_items`, `totals`, `fulfillments`, `shipping_address`, and `billing_address` values for custom Plunk templates and workflows. Order-backed transactional data is sent as non-persistent Plunk data so receipts do not overwrite long-lived contact profile fields.

### Plunk Template Variables For Fulfillment Emails

Fulfillment notifications expose top-level Plunk variables. Useful variables include:

- `{{store_name}}`, `{{store_code}}`, `{{store_url}}`
- `{{recipient_email}}`, `{{customer_email}}`, `{{customer_name}}`
- `{{order_number}}`, `{{order_total}}`
- `{{fulfillment_id}}`, `{{fulfillment_number}}`, `{{fulfillment_status}}`, `{{fulfilled_at}}`
- `{{delivery_method_name}}`, `{{stock_location_name}}`
- `{{tracking}}`, `{{tracking_url}}`, `{{tracking_link_html}}`
- `{{delivery_total}}`, `{{delivery_total_display}}`, `{{discount_total_display}}`
- `{{fulfillment_items_html}}` or `{{fulfillment_items_text}}`

The same payload also includes structured `fulfillment_items` for future API/workflow use. Fulfillment template data is sent as non-persistent Plunk data.

### Plunk Template Variables For Return Refund Emails

Return refund emails expose top-level Plunk variables. Useful variables include:

- `{{store_name}}`, `{{store_code}}`, `{{store_url}}`
- `{{recipient_email}}`, `{{customer_email}}`, `{{customer_name}}`
- `{{order_number}}`, `{{order_total}}`
- `{{return_id}}`, `{{return_number}}`, `{{return_status}}`
- `{{refund_total}}`, `{{refunded_total}}`, `{{refunded_total_display}}`, `{{refundable_total}}`, `{{refundable_total_display}}`
- `{{return_items_html}}` or `{{return_items_text}}`

The same payload also includes structured `return_items` values. Return template data is sent as non-persistent Plunk data.

The current order event is `spree.order.placed`; update workflows listening for the earlier `spree.order.completed` event. Current fulfillment and return events are `spree.fulfillment.fulfilled` and `spree.return.refunded`; update workflows using the earlier shipment and reimbursement event names. Update email templates using `order_state` or `payment_state` to use `status` or `payment_status`. Shipment and reimbursement template variables were also removed in favor of fulfillment and return names. These are intentional Spree 6 contract changes, so update Plunk workflows and templates when upgrading this extension.

## API Strategy

The current server-side integration intentionally uses:

- `POST /contacts` for contact upsert
- `POST /contacts` with explicit `subscribed: true` for subscribe flows
- `POST /contacts` with explicit `subscribed: false` for unsubscribe flows
- `POST /events/track` for event delivery after the contact has been ensured
- `POST /v1/send` for explicitly enabled direct transactional email handoff

This extension does not rely on `/v1/track` for server-side commerce sync. The reason is important: Plunk documents that `/v1/track` can auto-create a contact, and contacts created that way are subscribed by default. The extension avoids that path so consent stays explicit.

## Consent And Safety Rules

- behavioral activity does not imply marketing consent
- only explicit newsletter opt-in should set `subscribed: true`
- user, checkout, and order-backed contact creation should stay unsubscribed unless consent is known
- ordinary profile sync checks Plunk with `POST /contacts/lookup`, sends `subscribed: false` only when creating a contact, and omits it for existing contacts so their state (including snooze) is preserved; this endpoint must be available, and sync fails closed if lookup fails
- commerce events should preserve an existing customer consent state instead of downgrading or upgrading it implicitly
- the unsubscribe webhook is disabled by default
- webhook writeback only accepts explicit unsubscribe semantics; Plunk subscription state never verifies a Spree subscriber

## Inbound Unsubscribe Webhook

When enabled, the extension can receive Plunk unsubscribe callbacks and remove that integration store's local newsletter subscription. Subscribe callbacks are acknowledged as no-ops: a Plunk contact state does not prove mailbox ownership and cannot replace Spree's double opt-in flow.

Current behavior:

- requires explicit operator opt-in
- requires an authorization bearer token
- accepts explicit `contact.unsubscribed` semantics
- ignores `contact.subscribed` signals with the `spree_confirmation_required` reason
- looks up the local email in the store attached to that Plunk integration
- removes only that store's newsletter subscriber when Plunk unsubscribes the contact
- records the customer's consent source as `newsletter` when the local marketing flag changes
- preserves customer consent while another store still has a newsletter subscription
- suppresses Spree event publication during the unsubscribe writeback to avoid immediate echo loops
- ignores repeated deliveries when they include a unique execution, event, or delivery ID
- ignores Plunk's temporary `snooze` and `snooze_expired` events so a pause does not revoke Spree consent

### How The Webhook Works

The endpoint is:

```text
POST /plunk/webhooks/unsubscribe/:integration_id
```

The request flow is:

1. Spree finds the active Plunk integration by `integration_id`.
2. The webhook must be enabled for that integration or the endpoint returns `404`.
3. Spree checks the `Authorization` header and requires an exact bearer-token match.
4. Spree accepts the request only if the payload clearly indicates an unsubscribe state.
5. Spree resolves the contact email and removes the matching local newsletter subscription. A subscribe state is ignored and must be confirmed through Spree.
6. Duplicate deliveries are ignored so the endpoint stays idempotent.

The webhook processes these unsubscribe signals:

- `contact.subscribed: false`
- top-level `subscribed: false`
- event name `contact.unsubscribed`

Explicit `contact.subscribed: true`, top-level `subscribed: true`, and event name `contact.subscribed` are acknowledged as no-ops with reason `spree_confirmation_required`. Other values are rejected as `unsupported_payload`.

Events whose `event.reason` is `snooze` or `snooze_expired` are ignored. They represent a temporary Plunk pause, not a consent change in Spree.

The current implementation prefers the default Plunk webhook payload and extracts the email from:

- `contact.email`
- or top-level `email`

### How To Get The `Unsubscribe Webhook Authorization Token`

This token is not issued by Plunk.

It is a shared secret that you generate yourself and configure in both places:

1. Store it in Spree Admin as `Unsubscribe Webhook Authorization Token`.
2. Send the same value from the Plunk webhook step as:

```text
Authorization: Bearer your-secret-token
```

Example:

- Spree field `Unsubscribe Webhook Authorization Token`:
  - `12b61441e2177ef63ff91623a2c8da531c97bac8890172530f8c90a2ffb3012e`
- Plunk webhook header:
  - Name: `Authorization`
  - Value: `Bearer 12b61441e2177ef63ff91623a2c8da531c97bac8890172530f8c90a2ffb3012e`

Do not put `Bearer` in the header name field. The header name must be `Authorization`, and the `Bearer ` prefix belongs at the start of the header value.

Use a strong random value, for example:

```bash
openssl rand -hex 32
```

or:

```bash
ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'
```

### How To Configure The Unsubscribe Webhook In Plunk

Configure a Plunk workflow for `contact.unsubscribed`, send a public HTTP request, and authenticate it with a shared-secret header. Do not send `contact.subscribed` callbacks as a way to verify a Spree newsletter subscriber.

Recommended setup:

1. Save the Spree integration and obtain its prefixed ID from the Admin API.
2. In Plunk, create a workflow triggered by `contact.unsubscribed`.
3. Add a `Webhook` step.
4. Set the URL to your public Spree endpoint. In current Spree, integrations use prefixed params that normally look like `int_<encoded-id>`, so the final URL will usually look like:

   ```text
   https://your-spree-host.example.com/plunk/webhooks/unsubscribe/int_25Rf07xd9z
   ```

   The `int_25Rf07xd9z` part is not something you invent manually. It is the integration's prefixed `id`. Get it from the Plunk integration record in the Admin API response to `GET /api/v3/admin/integrations`; the current dashboard does not display a custom webhook URL.

5. Set the method to `POST`.
6. Add this header:

   ```json
   {
     "Authorization": "Bearer your-secret-token"
   }
   ```

   In the Plunk UI, that means:

   - `Name`: `Authorization`
   - `Value`: `Bearer your-secret-token`

7. Leave the body empty so Plunk sends its default payload.
8. Enable the workflow.

Notes:

- The webhook URL must be publicly reachable from Plunk.
- HTTPS is preferred.
- Plunk webhook delivery is workflow-based, so no workflow means no webhook.
- This extension is built to work with Plunk's default webhook payload shape.
- If you choose a custom webhook body, include the contact email, an explicit unsubscribe state, and `event.reason` when present. Replay protection needs a unique ID that your Plunk version can expose in a custom body; without one, identical payloads are processed because the endpoint cannot distinguish a retry from a later state change.
- The default body includes the unique workflow execution ID and event data, so leaving the body empty is recommended.

### Expected Local Result After A Plunk Unsubscribe

If Plunk flips a contact to unsubscribed and the webhook is configured correctly:

- only that integration store's `Spree::NewsletterSubscriber` row is deleted
- the customer's global `accepts_email_marketing` is cleared only when no newsletter subscriptions remain in any store
- repeating the same delivery should stay safe and idempotent

Spree stores newsletter subscriptions per store but keeps `accepts_email_marketing` on the global customer record. When that global flag changes, `spree_plunk` also refreshes Plunk integrations for other stores that already have a newsletter subscription for the customer.

When a customer changes their email address, `spree_plunk` resets their global marketing consent and removes their newsletter subscriber rows from every store. It syncs the current address as unsubscribed, but the current event path does not identify the old address, so cleanup of the old Plunk contact is not guaranteed. The new address stays unsubscribed until the customer opts in and completes newsletter confirmation again; changes limited to surrounding whitespace or ASCII letter case do not reset consent, while Unicode case-fold lookalikes are treated as different addresses. See [Newsletter Email Identity: Case And Whitespace](docs/transactional-email-inventory.md#newsletter-email-identity-case-and-whitespace) for the Spree normalization details.

## What This Extension Is For

This extension is a good fit when you want:

- Plunk to own marketing automation
- Spree customer and newsletter data to stay in sync with Plunk
- commerce events available inside Plunk workflows
- a consent-safe server-side integration without browser tracking as a requirement

## Out Of Scope

The current MVP intentionally does not cover:

- automatic removal or disabling of `spree_emails`
- invitation, report, export, or webhook system emails
- default-enabling Plunk transactional sends without an explicit operator decision per email type
- anonymous visitor tracking
- storefront public-key or browser-side tracking
- back-in-stock workflow parity
- campaign or workflow authoring inside Spree admin
