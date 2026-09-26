# How the App Store screenshots were made

The five screenshots on the listing (orange background, white headline, phone screen with
rounded corners) were generated on 11 Sep 2026. The uploaded copies live in App Store Connect;
the local originals were lost when macOS cleared its temp folder. To remake them:

1. Seed the LOCAL backend with demo data (never production): import `demo-plants.csv` as the
   manager, then create ~5 bills for invented customers with mixed Cash / UPI / Split / due.
   Invented names only - the screenshots are public.
2. Boot the largest iPhone simulator (iPhone 17 Pro Max = 1320x2868), light mode, and set a
   clean status bar:
   `xcrun simctl status_bar <id> override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3`
3. Install a Debug build and capture full-resolution PNGs with
   `xcrun simctl io <id> screenshot raw-NN.png` on these screens: the Bill grid; the review
   sheet with two plants; "Bill saved"; the Sales day; and Sales offline (stop the local
   server, switch tabs to force a reload, so the red banner and "saved at" note appear).
4. Compose each one with Python + Pillow: canvas 1320x2868, vertical gradient from #F05B01 to
   #FF8030, white SF Pro Rounded bold headline ~104px centred in the top ~340px, screenshot
   scaled to 80% width with 140px rounded corners and a soft drop shadow, bottom margin 70px.
   Save as RGB PNG (App Store Connect rejects transparency), then also resize to 1284x2778 and
   crop the extra bottom for the 6.5" slot.

Headlines used: "Make a bill in seconds", "Prices fill in for you", "Save it. Print it.",
"Today's sales at a glance", "Keeps working offline".
