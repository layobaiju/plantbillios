# Handover - Plantbill

Written 26 September 2026, before the work laptop was reset. It is the single place to catch up
on where the project stands. If something here disagrees with `claude.md`, trust this file:
`claude.md` describes the original 2026 plan and parts of it are now history.

---

## 1. Where everything runs

| Thing | Where |
|---|---|
| Production API | `https://api.plantbill.in` - FastAPI + PostgreSQL 16, self-hosted VPS in India (`187.127.157.119`, shell prompt `root@srv1782496`) |
| Website and web app | `https://plantbill.in` - React SPA built to `frontend/dist`, served by Nginx from the same VPS |
| Public web pages | `/login`, `/privacy` (and `/support`, written but not yet deployed) |
| Support page Apple uses | `https://sites.google.com/view/plantbill-contact` (Google Sites, public, free) |
| Deployment runbook | `info/VPS-DEPLOYMENT.md` - server paths, services, database roles |
| Git remotes | `plantbillios` (private, this handover), `origin` = Ahd4wnn/plantbilling (the VPS pulls from it), `plantpark` = layobaiju/billing-system-plantpark |

**The backend is shared.** The live Play Store app and the website run on the same API as iOS.
Backend changes need a deliberate, explicit decision each time, are built and tested only
against a local backend, and are never deployed automatically.

---

## 2. The iOS app today

- Bundle `com.dofida.Plantbill`, marketing version **1.0**, iOS 16 minimum, SwiftUI, zero
  external packages.
- Uploaded builds: **1** (old, pre-dates this work), **2** (11 Sep), **3** (20 Sep, current).
- Build 3 = build 2 plus two fixes:
  - A customer's phone number typed **without a name** used to be silently discarded, so a bill
    with money owed could land in Dues with no name and no phone. Now the app uses the name the
    returning-customer lookup already knows, or asks for one. (`BillingViewModel.checkout`)
  - The Printer screen no longer describes itself as "a Bluetooth fallback for testing", which
    reads to App Review like an unfinished feature.

Work completed earlier, matching the Android app screen by screen: the billing screen, review
sheet and printed receipt; offline copies of Sales, Customers and Dues; the "Powered by Dofida"
credit and the opening animation; the privacy manifest. Verified by hand: iPad compatibility
mode, AirPrint receipts, held bills, split payment with a due, the returning-customer lookup,
and the offline banner with its "saved at" note.

---

## 3. The App Store, and what is still owed

**History**

| When | What happened |
|---|---|
| 19 Aug | v1.0 (build 1) rejected - 2.1 App Completeness, no demo login given |
| 11 Sep | Build 2 uploaded, new screenshots made and uploaded, version resubmitted |
| 15 Sep | Rejected again, reviewed on iPhone 17 Pro Max and iPad Air 11-inch (M3) |
| 20 Sep | Build 3 uploaded |

The 15 Sep rejection had two parts, both answered in `info/appstore/apple-reply.txt`:

- **Guideline 1.5** - the Support URL in App Store Connect was `https://plantbill.in/support`,
  a page that was never published. Fixed by publishing the Google Sites page above; the URL in
  App Store Connect still has to be changed to it.
- **Guideline 2.1(b)** - Apple wanted the business model, suspecting paid content bought
  outside the App Store. The answer: nothing is sold in the app or outside it. No subscriptions,
  no in-app purchases, no paid tiers, no advertising. Shops are charged nothing at present; any
  future fee would be agreed directly with the business owner and settled off the app. The
  "scan to pay" QR only carries the shop's own UPI ID, so money never passes through the app.

Apple also sent the standard new-app information request (screen recording plus seven
questions); the same reply answers all of it.

**Still to do, all inside App Store Connect**

1. **Answer the export-compliance question on build 3.** Every build so far arrives marked
   "Missing Compliance", which is why TestFlight testers see "No Builds Available". Answer: the
   app uses encryption (HTTPS) and qualifies for the exemption - it only uses the standard
   TLS, Keychain and file protection built into iOS, with no custom cryptography.
2. **Record the demo video** on a physical iPhone running the newest iOS, following
   `info/appstore/recording-shot-list.txt`. Silent; about 2-3 minutes.
3. **Demo logins** for App Review: salesperson `adon@gmail.com` plus a manager account, and the
   demo shop needs plants and a few past bills so the reviewer sees a working app
   (`info/appstore/demo-plants.csv` can be imported as the manager).
4. **Fill in and resubmit**: Support URL, the notes from `info/appstore/app-review-notes.txt`
   (under Apple's 4,000-character limit), the reply from `info/appstore/apple-reply.txt` (also
   under 4,000), build 3 attached, then Resubmit to App Review.

The App Store screenshots currently on the listing are the orange set made on 11 Sep; the
originals were lost with a temp-folder cleanup, and `info/appstore/screenshots-recipe.md`
explains how to remake them.

---

## 4. Working agreements

These came out of earlier sessions and still hold:

- **The backend is shared with live users.** No changes without an explicit decision for that
  specific change, and never deployed by an assistant.
- **Credentials are the owner's.** Production and Apple passwords are typed by Adon, never
  handled, requested or stored by an assistant. The same goes for the server's root password.
- **The Apple account stays as it is:** team `9B9PT273HB`, Individual membership, seller name
  "Adon Joseph". Converting to an Organization (to show "Dofida" as the seller) was researched
  and deliberately dropped. Don't reopen it.
- **Browser work happens in Opera**, not Chrome. The Claude browser extension cannot drive
  Opera, so the working pattern is: put text on the clipboard, open the page with
  `open -a Opera <url>`, and give short click-by-click steps.
- **No self-signup.** Accounts are created for a shop by the platform owner. A signup-and-trial
  feature was built once and removed the same week; it is parked on the branch
  `self-signup-trial` if it is ever wanted again.

---

## 5. Setting up a fresh machine

**iOS**

    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    open Plantbill/Plantbill.xcodeproj

Debug builds point at a local backend (`http://localhost:8000` in the Simulator); Release builds
point at production - see `Plantbill/Plantbill/Core/Networking/BaseURLStore.swift`. To put the
app on a real iPhone, use TestFlight; the free personal-team signing used for the old iPhone X
expired on 16 Sep 2026.

Xcode must be signed in (Settings > Accounts) before any App Store upload - without it
`xcodebuild -exportArchive` fails with "Failed to find an account with App Store Connect access".

Upload a new build:

    # bump CURRENT_PROJECT_VERSION in project.pbxproj first - it must be higher than 3
    xcodebuild -project Plantbill/Plantbill.xcodeproj -scheme Plantbill -configuration Release \
      -destination 'generic/platform=iOS' -archivePath /tmp/pb.xcarchive -allowProvisioningUpdates archive
    xcodebuild -exportArchive -archivePath /tmp/pb.xcarchive -exportOptionsPlist ExportOptions.plist \
      -exportPath /tmp/pb-export -allowProvisioningUpdates

`ExportOptions.plist` needs: method `app-store-connect`, destination `upload`, teamID
`9B9PT273HB`, signingStyle `automatic`, manageAppVersionAndBuildNumber `false`.

**Backend (local only)**

    cd backend && python3 -m venv .venv && ./.venv/bin/pip install -r requirements.txt
    ./.venv/bin/alembic upgrade head
    ./.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000

Local development accounts (they exist only in a local database, never in production):
admin `owner@plantora.app`, owner `bigowner@plantpark.in`, manager `manager@plantpark.in`,
salesperson `cashier@plantpark.in` - passwords are the `Dev...!2026` set used by the seed data.

**Website**

    cd frontend && npm install && npm run dev

---

## 6. Known issues and next steps

1. **Export compliance is not declared.** Add `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`
   to the target's build settings (accurate: the app uses only standard HTTPS). Until then every
   upload needs the question answered by hand in App Store Connect, which blocks TestFlight.
2. **Duplicate customers.** The server creates a new customer row for every bill, so a repeat
   customer appears several times in the Customers list. It affects Android and the website too,
   so it is a backend decision, not an iOS one.
3. **Translations.** Roughly a third of the strings are still English in Hindi, Kannada and
   Tamil, plus everything added since. The English wording should be settled first.
4. **Voice search on a real device** has never been verified - the Simulator has no microphone.
   The matcher, the permission prompts and the UI are verified.
5. **The `/support` page for plantbill.in** is written (`frontend/src/pages/SupportPage.tsx` and
   `frontend/public/support.html`) but not deployed; Apple currently points at the Google Site.
   Deploying it needs a website release, which needs server access.
6. **iOS 16 runtime** is not installed in Xcode, so iOS 16 is compile-verified only; everything
   was run on iOS 26.
