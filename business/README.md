# Business edition: audit first, clear rarely

Everything else in this repo assumes the devices are yours and the history is yours to
erase. A business is different. Records may be something you are required to keep, and
clearing them can be a violation, not a clean-up.

## Read this before you clear anything

- **Retention rules can override privacy.** Regulated data (health records under HIPAA,
  controlled unclassified information under CMMC, tax and payroll records, contracts) often
  has a minimum keep period. Logs that prove who accessed what are part of that evidence.
- **A legal hold freezes everything.** If a dispute, investigation, or audit is open or
  expected, do not delete or reset anything that might be relevant. Ask counsel first.
- **Deleting evidence can be worse than the original problem.** The repo's report scripts
  are safe to run on a business machine because they delete nothing. Its `clear-*` scripts
  are not, and should not run on company devices until the owner of the retention policy
  agrees in writing.
- **Check your own policy.** Where this page names a retention length or a setting that
  varies by plan, it says "check your tenant". Look at your own settings, not at a number
  from a guide.

## Order of work

1. **Find out what you have.** Run [network/device-inventory](../network/device-inventory/)
   on each office network, then compare it to your asset list. Anything on the network but
   not on the list is the first thing to chase.
2. **Run the report-only audits** in [audit/](../audit/) on a sample of machines. They count
   and size history stores without reading them, so they show what is being kept.
3. **Lock down the network.** Work through [router-hygiene](../network/router-hygiene/),
   put guest and IoT devices on their own network, and see [pihole-tv](../network/pihole-tv/)
   for screens in meeting rooms.
4. **Work the lists in [what-businesses-forget.md](what-businesses-forget.md).**
5. **Only then decide what to clear,** with the retention owner, and clear the least you can.

## Household pages that still apply

Printers and copiers, retiring devices, and drives are the same problem at office scale.
See [consoles, printers, drives, and retiring devices](../household/consoles-printers-drives-retiring.md).
A copier or printer lease return is the most common way business data leaves the building.
