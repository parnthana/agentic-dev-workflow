# checkout-coupons
Let shoppers enter one coupon code at checkout to get a percentage off their cart.

- Each coupon has: code, percent (1-100), minimum spend, expiry date.
- One coupon per order. Entering a second code replaces the first.
- The discount applies to the item subtotal only, not to shipping.
- Show the discount as its own line in the cart summary and on the order confirmation.
- AC: cart subtotal 100, coupon 10% with minimum spend 50 -> discount 10, total 90 plus shipping.
- AC: cart subtotal 40, coupon minimum spend 50 -> the code is rejected with a message naming the minimum.
