# Plantbill

Billing software for plant nurseries and garden shops in India. A shop's staff make a customer
bill in a few taps, print the receipt, and see the day's sales, cash, expenses and unpaid dues.
It replaces the hand-written bill book at the counter. Many users are 50-75 years old, so every
screen is built for large text, one clear action, and plain language.

Four things live in this repository:

| Folder | What it is |
|---|---|
| `Plantbill/` | The iOS app (SwiftUI, iOS 16+, no third-party dependencies) |
| `android/` | The Android app (Jetpack Compose) - the feature reference for iOS |
| `frontend/` | The web app and public website (React + Vite), served at plantbill.in |
| `backend/` | The API for all three (FastAPI, PostgreSQL with row-level security) |
| `info/`, `docs/` | Deployment runbook, App Store material, feature notes |

**Start here: [HANDOVER.md](HANDOVER.md)** - current status, what is half-finished, the App
Store situation, how to set up a fresh machine, and the working agreements for this project.

One rule above all others: `api.plantbill.in` serves the live Android app and the website as
well as iOS. Nothing changes there without a deliberate decision.
