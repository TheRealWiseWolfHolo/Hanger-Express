# Hanger Express

SwiftUI iOS prototype for retrieving and organizing a Star Citizen hangar.

## Current Focus

- Build a safe, read-only first experience for hangar organization.
- Normalize RSI hangar data into app-owned models for packages, fleet ships, and buy-back entries.
- Keep destructive actions like melt, gift, and upgrade out of v1.

## Repo Shape

```text
Hanger Express/
  App/
  Core/
    Domain/
    Protocols/
  Features/
    Buyback/
    Fleet/
    Hangar/
    Onboarding/
    Shell/
    Settings/
  Services/
    Preview/
  Shared/
docs/
  ARCHITECTURE.md
```

## Live Integration Strategy

The app shell currently uses preview data so we can settle the product structure first. The intended live path is:

1. Sign in through a browser-backed session flow.
2. Capture an authenticated session without storing the RSI account password.
3. Sync hangar pages, buy-back pages, and selected metadata into normalized local models.
4. Organize locally with filters, grouping, notes, and future alerting.

More detail is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
