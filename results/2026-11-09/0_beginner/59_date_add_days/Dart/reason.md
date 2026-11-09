Replace forward day advancement with backward advancement and the displayed + with -. On day dropping below 1, move to the preceding month (or December of the preceding year), then set the day to that destination month length using its Gregorian leap year. In the 120-day case, 2023-11-01 must step to 2023-10-31; repeated backward steps reach 2023-07-18.

c retains the original components while y,m,d evolve. Reverse d++/month/year overflow into underflow handling; lengths and the leap test must use destination values before choosing the new day. date formats both sides without altering c.

Date fields, month lengths/leap rule, rollover update and display identify all backward-step changes. Forward-only day increments without destination-month logic would be insufficient.
