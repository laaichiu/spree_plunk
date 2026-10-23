# Plunk Email Templates

This directory contains copy-ready examples for Plunk. `spree_plunk` does not create, import, publish, or synchronize these templates; manage them in Plunk and copy the resulting IDs into the matching Spree integration preferences when you want Plunk templates as a fallback.

For customer email editing in Spree Admin, use **Settings → Emails → Templates** instead. A published Spree template takes precedence over the corresponding Plunk template ID. The store-owner notification is operator-facing and remains Plunk-template-only.

## Setup

1. Create a template in Plunk.
2. Choose `Transactional` for files under `transactional/` or `Marketing` for files under `marketing/`.
3. Use the suggested name and subject below. The subjects match the current `spree_plunk` presenter subjects; customize them only if you intend to keep that change in sync yourself.
4. Paste the file contents into Plunk's HTML editor and save the template.
5. Copy the saved template ID into the matching Spree integration preference. Order confirmation resends share the order confirmation template ID.

For transactional sends, configure the sender email and name in the Spree Plunk integration. The sender domain must be verified in Plunk. For campaigns, use the sender identity configured for the Plunk project/campaign.

## Transactional Templates

| Spree integration preference | Plunk template type | Suggested template name | Suggested subject | HTML file |
| --- | --- | --- | --- | --- |
| Password Reset Template ID | Transactional | Spree Password Reset | `Reset your {{store_name ?? Shop}} password` | [`transactional/password-reset.html`](transactional/password-reset.html) |
| Newsletter Confirmation Template ID | Transactional | Spree Newsletter Confirmation | `Confirm your {{store_name ?? Shop}} newsletter subscription` | [`transactional/newsletter-confirmation.html`](transactional/newsletter-confirmation.html) |
| Order Confirmation Template ID | Transactional | Spree Order Confirmation | `Your {{store_name ?? Shop}} order confirmation {{order_number}}` | [`transactional/order-confirmation.html`](transactional/order-confirmation.html) |
| Order Cancellation Template ID | Transactional | Spree Order Cancellation | `Your {{store_name ?? Shop}} order {{order_number}} was canceled` | [`transactional/order-cancellation.html`](transactional/order-cancellation.html) |
| Fulfillment Template ID | Transactional | Spree Fulfillment Fulfilled | `Your {{store_name ?? Shop}} order {{order_number}} has shipped` | [`transactional/fulfillment-fulfilled.html`](transactional/fulfillment-fulfilled.html) |
| Return Refund Template ID | Transactional | Spree Return Refunded | `Your {{store_name ?? Shop}} refund for order {{order_number}}` | [`transactional/return-refunded.html`](transactional/return-refunded.html) |
| Store Owner Notification Template ID | Transactional | Spree Store Owner Notification | `New order for {{store_name ?? Shop}}` | [`transactional/store-owner-notification.html`](transactional/store-owner-notification.html) |

The store-owner notification goes to the store's configured new-order notification address. It is an operational email, not a customer receipt.

### Variables Used By Each Transactional Template

| Template | Spree-provided variables used |
| --- | --- |
| Password reset | `store_name`, `recipient_email`, `reset_url` |
| Newsletter confirmation | `store_name`, `recipient_email`, `confirmation_url` |
| Order confirmation | `store_name`, `order_number`, `customer_first_name`, `order_total`, `line_items_html`, `totals_html`, `shipping_address_text`; `store_url` is optional |
| Order cancellation | `store_name`, `order_number`, `customer_first_name`, `order_total`, `line_items_html`, `totals_html`; `store_url` is optional |
| Fulfillment fulfilled | `store_name`, `order_number`, `customer_name`, `fulfillment_number`, `delivery_method_name`, `tracking`, `fulfillment_items_html`; `tracking_url` is optional |
| Return refunded | `store_name`, `order_number`, `customer_name`, `return_number`, `refunded_total_display`, `return_items_html`; `store_url` is optional |
| Store-owner notification | `store_name`, `order_number`, `customer_name`, `customer_email`, `order_total`, `line_items_html`, `totals_html`; `store_url` is optional |

## Marketing Template

| Use | Plunk template type | Suggested template name | Suggested subject | HTML file |
| --- | --- | --- | --- | --- |
| Campaigns, newsletters, winback, post-purchase marketing | Marketing | Store Campaign | `New arrivals from {{store_name ?? Shop}}` | [`marketing/store-campaign.html`](marketing/store-campaign.html) |

Use Plunk's marketing unsubscribe footer and sending controls. Do not use this template for password resets, order receipts, fulfillment, or refund messages.

## Variables And Editing

Plunk renders data values supplied by `spree_plunk` as top-level template variables, such as `{{order_number}}`; use `{{data.order_number}}` only when intentionally addressing the nested data object. Plunk supports Liquid control flow and loops, as well as the legacy `{{variable ?? fallback}}` form used here. The text after `??` is a literal fallback.

The marketing example's `campaign_*`, `feature_*`, and `primary_cta_*` values are sample campaign data. `spree_plunk` does not populate those values; provide them through your Plunk campaign/template setup. The transactional variables above are supplied by `spree_plunk` when it sends the corresponding email type.

These examples use pre-rendered HTML fragments for predictable email-safe markup and simpler templates:

- `{{line_items_html}}`
- `{{totals_html}}`
- `{{fulfillments_html}}`
- `{{fulfillment_items_html}}`
- `{{return_items_html}}`

The corresponding structured arrays are also sent for custom Plunk templates and workflows. Plunk does not automatically HTML-escape scalar values: use Liquid's `| escape` filter for customer, store, order, and campaign values in HTML text or attributes. The pre-rendered HTML fragments are already escaped by `spree_plunk` and must remain unescaped when inserted into the HTML body. If a link URL is optional, the examples hide its button when the value is blank rather than sending recipients to a placeholder URL.
