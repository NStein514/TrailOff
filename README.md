# TrailOff

TrailOff helps people explore outdoors: discover trails, download offline maps, record GPS routes, and save adventures. The current app includes a trail catalogue with route geometry, plan-aware recording with off-route warnings, on-device hike history with photo albums per trip, GPX sharing, offline map regions, saved-route recommendations, a plan-aware packing checklist, offline trail answers, and a Constellation sky view.

## Product scope

- Discover trails and match them to the hiker. *(Implemented: sample catalogue with ability and condition fit.)*
- Recommend routes based on hiker ability and trail conditions. *(Implemented: ranks saved hikes against ability and conditions.)*
- Generate practical packing checklists for the selected route and conditions. *(Implemented: built from the planned route's distance, ascent, walking time and high point, plus ability and conditions.)*
- Answer questions grounded in downloaded trail information. *(Implemented: offline retrieval that quotes a downloaded guide section.)*
- Support outdoor activities beyond hiking, including camping. *(Constellation sky view implemented.)*

## Trail discovery

Open **Discover trails** from the dashboard to browse the region's routes. Each card shows distance, ascent, time and a fit badge: *Fits today*, *A stretch*, or *Too demanding today*. Fit is the larger of distance and ascent measured against the selected ability's limits, reduced by the selected conditions. Changing ability or conditions re-sorts the list and updates every badge. Tapping a route opens details with the fit reasoning and route-specific notes.

The catalogue is sample data bundled with the app, and fit is judged only from the hiker's own settings. It does not know about closures, permissions, or the weather on the day.

## Planning a trail

Open a route and choose **Plan this trail** to make it the current objective. The plan is stored on the device and shown on the dashboard as a **Your plan** card with its distance, ascent, time and fit badge. Because the badge is recalculated from the dashboard's ability and conditions, changing those settings immediately shows whether the plan still suits the day. The catalogue marks the planned route and the same sheet offers **Remove from plan**; the dashboard card can clear it too.

Planning also drives the map and the offline download. Each catalogue trail carries a route line, so the dashboard map frames and draws the planned route — as a MapLibre line on device, and as a painted trail with a trailhead marker in the no-device fallback, where the tour labels and demo route are hidden so they can't be mistaken for another trail. The map card labels the plan. The record tab's live track is projected in the same frame as the planned line, so you can see how far your walk sits from it.

The offline download saves the planned route's bounding box widened by 1.5 km on every side, so the saved tiles cover the line the map draws, and reports the saved area by name. Each trail has its own saved area, so the button shows *Map saved* only for the plan currently selected and re-checks whenever the plan changes.

Limits: the route geometry is sample data written for demonstration. It starts and closes at each trailhead and stays within one valley, but it is not a surveyed track and is shorter than the curated distance printed beside it, which remains the authoritative figure. The saved area is the route's bounding box, not a corridor buffered along the line, so a wide loop still downloads its empty interior. And a plan still does not navigate: the live hike card measures distance and bearing back to the trailhead, but nothing gives turn-by-turn directions along the route.

## Recording on a planned trail

While a plan is active, the live hike card gains a **Back to _trail_ trailhead** row: the straight-line distance and a compass bearing from the latest GPS fix back to the trailhead, with an arrow that rotates to that bearing and a plain *You are at the trailhead* once you are within 30 m. It is a heading and a distance, not a route: it ignores terrain, cliffs and where the path actually goes, so it is for orientation only.

Recording also watches where you are relative to the planned line. Once the latest fix is more than 200 m from the nearest point of the route, the card shows an off-route warning with that distance rounded to the nearest 10 m. The warning only clears once you are back within 120 m, so GPS noise at the boundary cannot flicker it. Distances are straight-line and measured against the drawn sample geometry, so they describe how far you are from the line on the map and nothing more — it cannot see cliffs, rivers or private land between you and that line, and it is not a safety system.

Saving a hike records which trail it was planned for. **Past adventures** then lists the trail under the date, and the shared GPX track is named after it. Hikes saved before planning existed still load and simply have no trail.

## Trip photo albums

Every saved adventure has an album. In **Past adventures**, tap the photo button on a trip row — it carries a count badge once photos exist — to open that trip's album. From there **Take photo** opens the system camera and the gallery action adds an existing picture from the library. Photos are copied into the app's private documents folder, with their trip association kept alongside the hike's start time, so albums survive restarts without an account, a network call, or access to the device's shared gallery.

Photos appear as a two-column grid; tapping one opens it full screen (pinch to zoom) with its capture time, and deleting it asks for confirmation first and removes the file from the device. Photos are stored at a maximum of 2000 px and 85% quality.

Limits: photos can only be added once a hike is saved, not while it is being recorded. There is no backup, sync or export — photos live in app storage and are lost if the app is uninstalled — and GPX export does not include them. EXIF location and camera metadata are not read or displayed, and the album does not know where a photo was taken.

## Packing for the plan

The checklist is built from the planned route as well as the day's ability and conditions. Water is estimated from the route's walking time at half a litre an hour, raised for heat and rounded up to the nearest half litre; a route over three hours or 500 m of ascent adds **Extra food**; 500 m of ascent adds **Trekking poles**; a high point above 1800 m adds an **Insulating layer**. The card names what it was built for (*Tailored to Lac du Portillon loop · 12.4 km · +1120 m*), and ticking items resets when the route or conditions change so a new plan starts unpacked. With no plan the list falls back to general essentials.

These are rules of thumb, not a substitute for judgement. They do not know your pace, medical needs, water sources along the route, or the forecast for the day.

## Trail answers

Download a region's trail guide, then ask questions about it with no signal. Answers are produced on device by matching the question against the downloaded sections and quoting the section that covers it, so every reply names its source (`From Tour du Portillon · Water & refills`). Questions that mention anything the guide does not discuss are refused instead of answered, and the app lists the topics the guide actually covers.

This is offline keyword retrieval over downloaded text, not a language model, and it does not know about live weather, closures, or current conditions. The guide currently bundled with the app is sample content; replace it with real downloaded guide data before relying on it. Safety-critical details such as access, rules, and hazards should always be checked with local sources.

## Constellation sky view

Open **Constellation** on the dashboard, choose **Use my location**, then point the back of the phone at the sky. The camera-free `CustomPainter` chart uses GPS and UTC time for a small offline catalog of 21 bright stars. Android rotation-vector fusion (compass, gyro and accelerometer) and iOS Core Motion true-north attitude align the chart, including display rotation and roll. Android applies location-dependent magnetic declination. Unavailable, unreliable or stale orientation falls back to a clearly labeled draggable manual view. Location can be refreshed after moving; it is refreshed on resume. No background tracking is added.

The chart is approximate: J2000 catalog coordinates with sidereal-time conversion, without precession, proper motion or atmospheric refraction. It is not a telescope alignment tool. Stars remain charted during daylight. This release does not include planets, constellation outlines, or a complete star/satellite catalog.

### Satellite setup and limits

This first version supports **ISS (25544) and Hubble (20580)** via the [N2YO REST API](https://www.n2yo.com/api/), documentation reviewed October 31, 2026. Obtain a personal N2YO key and run:

```sh
flutter run --dart-define=N2YO_API_KEY=YOUR_PERSONAL_KEY
```

No key is committed or supplied by default. Without a key, stars and orientation still work and the satellite switch explains why predictions are unavailable. Users explicitly enable live predictions before their observer coordinates are sent to N2YO. A build-time key is recoverable from the app binary: use personal builds for this setup; a shared production deployment needs a server-side credential and quota proxy. Do not commit keys or log request URLs.

While enabled and foregrounded, the app requests five minutes of timestamped observer-relative positions plus one day of optical passes for each supported satellite, refreshing every four minutes. This is 30 position and 30 optical-pass requests per hour of continuous use, below N2YO's documented per-key hourly limits (1000 and 100 respectively). Reopening or toggling can consume extra quota. Network, authorization, malformed-data and quota failures hide satellite overlays and retry on the next interval; position samples are never extrapolated. Responses must match the requested NORAD IDs and contain consecutive integer-second timestamps starting within 30 seconds of the request and covering the current time. Between adjacent samples, normalized direction vectors provide smooth movement across north. Data outside its actual timestamp coverage is labeled unavailable, not as an empty visibility prediction. No satellite data is persisted. Successful responses display their fetch time; provider orbital-element age is not supplied by these endpoints.

Only above-horizon samples inside a predicted **fully visible** pass are drawn. N2YO sometimes returns a visible duration shorter than the pass interval without identifying the exact illuminated subinterval; those ambiguous passes are conservatively omitted. An empty chart does not mean no satellites exist overhead. Weather, terrain, brightness, data errors and compass interference can prevent sightings. Sensors align predictions; they cannot identify an observed light.

### Verification

`flutter test` covers celestial coordinates, projection and roll, horizon/behind-view rejection, provider parsing and errors, partial visibility, sample expiry, location/manual/sensor fallback, suspension during location acquisition, sensor reconnection, malformed/ended streams, and late satellite responses. Permission-dialog inactivity preserves the pending location request; background suspension invalidates it and obtains a fresh fix on resume. `flutter analyze` checks Dart integration. Native sensor alignment still needs a physical Android/iOS device check (true north, overhead, roll, landscape, magnetic interference, pause/resume, denied permissions); an emulator cannot validate compass accuracy. iOS builds require macOS/Xcode.

Orientation references: [Android SensorManager](https://developer.android.com/reference/android/hardware/SensorManager), [Apple true-north attitude](https://developer.apple.com/documentation/coremotion/cmattitudereferenceframe/xtruenorthzvertical).
