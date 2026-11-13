# Shopify orders awaiting contact details

Seallo Connect imports otherwise eligible Moroccan MAD cash-on-delivery orders even when a customer name, phone, city or street address is missing. Invalid phone numbers also require review. The order remains New, with its original products, shipping amount, total and import identity. The order list, order detail and confirmation queue show a contact alert in French, English and Arabic.

A missing phone or name does not create a fabricated customer profile. Separate orders without phone numbers remain separate. Confirmation calls, stock reservation and Sendit dispatch stay blocked until a workspace administrator saves complete contact details through the order's contact form. This correction changes only Morea's delivery contact; it does not write back to Shopify or unlock imported prices/products.

Normal manual checkout/order creation still requires complete contacts. Other Shopify eligibility restrictions remain: unpaid/unfulfilled COD orders in MAD shipping to Morocco, with supported totals and no taxes or discounts. Malformed types and oversized contact values remain rejected.

## Verify before Shopify resubmission

Use synthetic data in a development store. Place an eligible order with the optional checkout phone omitted. Verify that it appears once in Morea with the alert, including after repeated webhook deliveries and catch-up sync. Verify that confirmation and shipping are blocked. Fill the contact form as a manager, then confirm normally; the original items, total and source order must remain unchanged. Verify an agent can see the alert but cannot use the contact correction endpoint. Record a screencast showing this complete path and verify the deployed application, not only the pull request.

Scheduled and manual catch-up sync also retry a bounded batch of existing `invalid_contact` rejections using Shopify's authorized order API. Recovery depends on the order still being available to the app and satisfying its normal eligibility rules. No real provider writes are needed for automated regression tests.

The migration permits absent contact/customer columns only for flagged orders, and flagged orders remain New or Cancelled at the database boundary. Rollback refuses to restore required columns while unresolved null contacts exist; complete or resolve those reviews first. No existing rejected payloads or customer data are copied into a new storage table.
