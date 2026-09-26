# Plantora — Project Context

> **Read [HANDOVER.md](HANDOVER.md) first.** It has the current state of the project
> (September 2026): the shipped iOS app, the App Store submission, and what is still open.
> The notes below are the original product brief — parts of them (printing, WhatsApp delivery,
> the role names, the "to do" list) have since been built or superseded.

## What this is
Plantora is a mobile-first billing PWA for plant shops in India. One platform admin (the owner) creates billing accounts for individual shops; each shop's data is fully isolated. End users are often elderly shop owners (60–80), so the shop-facing app must be simple, legible, reliable, and forgiving.

## Who uses it
- **Shop owner** (`shop_owner`): the daily user. Phone-first. Often elderly. Makes bills, manages products, views sales + daily cash book.
- **Admin** (the platform owner / me): creates and manages shops, views a cross-shop customer directory. Uses laptop or phone. Denser, conventional UI is fine here.

## Stack
- **Frontend:** React 18 + Vite + TypeScript, Tailwind CSS, React Router, Zustand (auth store), Axios, Framer Motion (sparingly), vite-plugin-pwa. Icons: **lucide-react**.
- **Backend:** Python 3.12, FastAPI, SQLAlchemy 2.0 (typed ORM), Alembic migrations, python-jose (JWT), passlib[bcrypt].
- **Database:** PostgreSQL 16, self-hosted (local in dev, same Postgres on the VPS later — NOT Supabase, by design, for cost + latency).
- **Hosting (later):** single VPS in an India region, Nginx reverse proxy + systemd + Let's Encrypt SSL. Product images on the VPS filesystem, served by Nginx; paths stored in Postgres.

## Architecture principles (do not violate)
- **Multi-tenancy via Postgres Row Level Security.** Tenant tables carry `shop_id`; the app connects as a non-superuser, non-BYPASSRLS role; the request sets `app.user_role` and `app.current_shop_id` via `SET LOCAL` from JWT claims, and RLS enforces isolation. Admin role reads across all shops. NEVER filter by shop_id manually in place of RLS; let RLS do it. On insert, take shop_id from the JWT, never the request body.
- **Server is the source of truth for all money.** Never trust totals/discounts from the client. All money is `Decimal` / `NUMERIC(12,2)`, quantized 2dp ROUND_HALF_UP. Never floats.
- **Saving a sale is independent of any delivery (print/WhatsApp).** A bill is committed atomically (bill + items + side effects in one transaction) before any print/share is attempted. No delivery failure may ever affect a saved sale.
- **Idempotency on checkout.** Each checkout attempt sends a client-generated idempotency key; the same key returns the same bill (no duplicates from double-taps). Enforced with a unique constraint.
- **Reproducibility.** Schema and RLS live in Alembic migrations, never applied by hand. Same Postgres major version local and prod. All config via env vars; secrets never committed.

## Roles & auth
- Accounts are admin-created only — NO public/self-signup.
- JWT carries sub, role (`admin` | `shop_owner`), shop_id (null for admin). Long-lived sessions (personal shop devices).
- Local dev admin (`admin@gmail.com` / a dev password) must NEVER be used in production — prod admin gets a fresh strong password set on the server.

## Design objective (READ CAREFULLY — current UI is too plain/cheap; this is the fix)
The aesthetic is **Apple / Stripe / Linear: minimal done with CRAFT, not minimal as absence.** The current shop UI looks lifeless and cheap because it's bare (gray boxes, default type, flat buttons). Minimal-done-well is rich: deliberate typography, generous and intentional spacing, depth (soft shadows, subtle layering), a confident botanical-green accent, smooth micro-interactions, and polish in the details. Restraint, not emptiness.

But the shop-owner app deliberately DIVERGES from Stripe/Apple toward elderly-friendliness:
- **Legibility over delicacy:** base font 17px+, medium/semibold weights (never light/thin), high contrast, near-black text (not gray) for primary content. No tiny low-contrast labels.
- **Obvious affordances:** buttons unmistakably look pressable (solid fills, clear edges, real depth). Min 48px touch targets; primary actions 56px, full-width on mobile.
- **Forgiveness:** every action has clear loading / success / error states in plain language. Nothing silent. No raw error codes.
- **One clear primary action per screen.** Calm, uncluttered, confident.
Net: "Apple's calm + Stripe's clarity + real craft, scaled up for older eyes and thumbs." Minimal in layout, never minimal in legibility or polish.

The **admin panel** uses the same design tokens (colors, type, green accent) but can be denser/conventional (tables, more per screen); responsive desktop + mobile.

Icons: use **lucide-react** throughout.

## App structure (shop-owner, phone-first)
Bottom navigation, large labeled tabs (labels always visible):
- **Bill** (default/home): the core billing screen.
- **Products**: catalog management.
- **Sales**: bill history + today's summary + the daily cash book.
- **More/Settings**: shop profile, preferences, logout. (Still a placeholder — to be built.)

## Billing model (UPDATED — single mode, all prices editable)
- **One billing mode** (the retail/wholesale toggle is being REMOVED). Rationale: plants of the same kind sell at different prices by size, so every price is inherently adjustable — retail and wholesale had become the same mechanism.
- Tapping a product adds it; its price is **pre-filled from the product's saved price but always editable per line** (size-based pricing is normal). Quantity via large +/− steppers.
- **Discount:** flat ₹ by default, with a % toggle. Discount can't exceed subtotal; % can't exceed 100. Server validates.
- **Payment:** Cash / UPI / Split. Stored as two amounts (`cash_amount`, `upi_amount`); method derived from which are non-zero. Hard rule: cash + UPI must equal the post-discount total, enforced server-side. Split auto-fills the remainder.
- **Customer:** name + phone entered fresh each bill (the "select existing customer" feature is being REMOVED — always type name + number). Customer is optional. Phone field is labeled for purpose (so a given number is informed consent for future receipts).
- Bill line items are denormalized (product_name + unit_price captured at sale time) so historical bills never change.

## Daily cash book (NEW — to be built)
- **Opening balance** and **closing balance** per day, both editable.
- **Expense tracking:** daily expense entries (e.g. electricity, supplies) with amount + note.
- **End-of-day reconciliation:** opening + cash sales − cash expenses = expected closing, shown against the actual closing balance the owner enters. The number the owner cares about at night.
- Today's summary keeps: total sales, bill count, cash vs UPI split. (Retail/wholesale split is dropped with the mode merge.)

## Admin features
- Create shop + first owner; list shops; activate/deactivate; reset password (credentials shown once, copyable).
- **Cross-shop customer directory:** lists customers across all shops. NEW changes: **de-duplicate by phone number** (no repeated numbers), and add **CSV export** (admin-only). Read-only.
- Privacy: this directory holds end-customers' personal contact data across shops. Admin-auth only; be deliberate (India DPDP). A visible privacy note in the UI; export is admin-only.

## Removed / changed from earlier builds
- **Stock:** removed from the shop UI. (Decide: hide from UI vs drop the column — currently leaning hide/ignore, keep column harmless. TBD.)
- **Retail/wholesale toggle:** removed → single editable-price billing mode.
- **Existing-customer selection:** removed → always enter name + phone fresh.

## Deferred (do NOT build yet — being rethought)
- **Printing.** Cross-platform problem: shops are a MIX of Android and iPhone. Android can use RawBT + Bluetooth thermal; iPhone (any browser — all are WebKit, no Web Bluetooth) CANNOT drive Bluetooth printers from the web and needs AirPrint (Wi-Fi printer). Likely resolution: standardize on a single Wi-Fi/AirPrint thermal printer so both platforms print via the browser. NOT decided/built. Bill success + bill detail screens have disabled Print placeholders.
- **WhatsApp bill delivery.** Being reconsidered. Options explored: `wa.me` manual link (free, no risk), self-hosted OpenWA (unofficial, ban risk — leaning AGAINST), and official BSP (e.g. Interakt by Jio/Haptik — official, no ban risk, has a fee — leaning toward). Whatever path, keep delivery behind a single `send_bill_whatsapp()`-style abstraction with swappable backends + a `wa.me` fallback, and consent-gated (only send to numbers the customer willingly gave; permanent opt-out honored). Bill screens have disabled Share placeholders.

## Status
Built & working: backend foundation (schema, RLS, auth), products API + UI, billing API + screen, sales screen, admin panel.
To do: this billing-model refactor (merge modes, editable prices, drop existing-customer), remove stock from UI, the visual/craft overhaul of the shop UI, the daily cash book (opening/closing/expenses), admin de-dup + CSV export, Settings/More tab, PWA polish, then VPS deployment. Printer + WhatsApp deferred.

## Conventions
- Plain-language, friendly error/empty/loading states everywhere (audience is elderly).
- Consistent ₹ formatting, 2 decimals, large legible numbers.
- Timezone Asia/Kolkata for day boundaries and summaries.
- Don't expose internal mechanics to the shop owner.