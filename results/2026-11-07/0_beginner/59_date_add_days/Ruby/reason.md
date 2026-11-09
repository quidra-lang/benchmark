Replace forward day advancement with backward advancement and the displayed + with -. On day dropping below 1, move to the preceding month (or December of the preceding year), then set the day to that destination month length using its Gregorian leap year. In the 120-day case, 2023-11-01 must step to 2023-10-31; repeated backward steps reach 2023-07-18.

original is formatted before year/month/day mutate. Reverse the increment/overflow block, recomputing lengths after any year/month rollback; format_date already zero-pads the result.

Date fields, month lengths/leap rule, rollover update and display identify all backward-step changes. Forward-only day increments without destination-month logic would be insufficient.
