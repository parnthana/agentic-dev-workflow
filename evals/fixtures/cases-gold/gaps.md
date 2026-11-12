# Product-gap heuristics (synthetic example). One line per dimension to walk; the trailing (why: ...) names the
# incident the line was learned from, so the leave-one-out arm (C) can drop it.
- Any rule checked once on entry: what if the inputs change afterwards, before the final step? (why: coupon-revalidate)
- Anything with an expiry or window: what if it ends between two steps of the same flow? (why: coupon-time-gap)
- Any computed amount shown on more than one surface: do all surfaces round the same way? (why: discount-rounding)
- Who can do this, and what does a user without permission see?
- What happens on a repeated or concurrent submit of the same action?
- What does an empty, zero or maximum value do?
