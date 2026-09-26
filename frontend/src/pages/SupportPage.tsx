/**
 * Public support page, served at /support (no auth). Apple requires the App
 * Store "Support URL" to lead to a page where a user can actually reach a
 * human — the sign-in page and the privacy policy don't qualify, which is what
 * the 1.5 Developer Information rejection was about.
 *
 * Keep the contacts here identical to the ones inside the apps (login screen
 * and More → Support). If a number or address changes, change it in all three.
 */
const WHATSAPP_DIGITS = "917975402266";
const PHONE_DISPLAY = "+91 79754 02266";
const EMAIL = "plantparkgroup@gmail.com";

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="space-y-2">
      <h2 className="text-xl font-bold text-ink">{title}</h2>
      <div className="space-y-2 text-base leading-relaxed text-ink-soft">{children}</div>
    </section>
  );
}

function ContactRow({ label, value, href }: { label: string; value: string; href: string }) {
  return (
    <a
      href={href}
      className="flex items-center justify-between gap-4 rounded-xl border border-black/10 bg-white px-5 py-4 transition hover:border-primary-700"
    >
      <span className="text-base font-semibold text-ink">{label}</span>
      <span className="text-base font-semibold text-primary-700">{value}</span>
    </a>
  );
}

export function SupportPage() {
  return (
    <div className="min-h-dvh bg-surface-muted px-6 py-12">
      <div className="mx-auto w-full max-w-2xl space-y-8">
        <header className="space-y-2">
          <div className="flex items-center gap-3">
            <img src="/logo.png" alt="PlantBill" width={48} height={48} className="rounded-xl" style={{ height: 48, width: 48 }} />
            <h1 className="text-3xl font-extrabold tracking-tight text-ink">PlantBill — Support</h1>
          </div>
          <p className="text-sm text-ink-soft">Billing software for plant nurseries and garden shops.</p>
        </header>

        <p className="text-base leading-relaxed text-ink-soft">
          Need help with the app, your shop's account, or a bill? Contact us directly — we answer in English, Malayalam,
          Hindi, Kannada and Tamil.
        </p>

        <div className="space-y-3">
          <ContactRow label="WhatsApp" value={PHONE_DISPLAY} href={`https://wa.me/${WHATSAPP_DIGITS}`} />
          <ContactRow label="Phone" value={PHONE_DISPLAY} href={`tel:+${WHATSAPP_DIGITS}`} />
          <ContactRow label="Email" value={EMAIL} href={`mailto:${EMAIL}`} />
        </div>

        <p className="text-base leading-relaxed text-ink-soft">
          We usually reply the same day, Monday to Saturday, 9 AM to 7 PM IST.
        </p>

        <Section title="Getting an account">
          <p>
            PlantBill accounts are created for a shop by us — there is no public sign-up, because each account belongs to
            a specific business and its own plant catalogue. To start using PlantBill at your nursery, message us on
            WhatsApp or send an email and we will set the shop up for you.
          </p>
          <p>
            Staff logins (manager and salesperson) are created inside the app by the shop's own manager or owner, under
            More → Salespeople.
          </p>
        </Section>

        <Section title="Forgot your password">
          <p>
            Ask your shop's manager or owner to reset it under More → Salespeople. If you are the owner, contact us at
            the number or email above and we will reset it for you.
          </p>
        </Section>

        <Section title="Printing a bill">
          <p>
            Tap Print on a saved bill. iPhone and iPad print through AirPrint, so a Wi-Fi printer on the same network is
            found automatically. Android phones print to a Bluetooth thermal printer.
          </p>
        </Section>

        <Section title="If the internet goes down">
          <p>
            The app keeps working for the things a counter needs: your plant list, today's sales, your customers and the
            dues list stay readable from the copy saved on the phone, and a bill can be held until the connection comes
            back. Anything shown from that saved copy is labelled with the time it was saved.
          </p>
        </Section>

        <Section title="Deleting your data">
          <p>
            Write to us at{" "}
            <a href={`mailto:${EMAIL}`} className="font-semibold text-primary-700 underline">
              {EMAIL}
            </a>{" "}
            and we will delete a shop's account and its records, or a customer's contact details, as described in our{" "}
            <a href="/privacy" className="font-semibold text-primary-700 underline">
              Privacy Policy
            </a>
            .
          </p>
        </Section>
      </div>
    </div>
  );
}
