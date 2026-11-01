# TrailOff

TrailOff helps people explore outdoors: discover trails, download offline maps, record GPS routes, and save adventures. The current app includes a trail catalogue, on-device hike history, GPX sharing, offline map regions, saved-route recommendations, a condition-aware packing checklist, offline trail answers, and a Constellation sky view.

## Product scope

- Discover trails and match them to the hiker. *(Implemented: sample catalogue with ability and condition fit.)*
- Recommend routes based on hiker ability and trail conditions. *(Implemented: ranks saved hikes against ability and conditions.)*
- Generate practical packing checklists for the selected route and conditions. *(Implemented.)*
- Answer questions grounded in downloaded trail information. *(Implemented: offline retrieval that quotes a downloaded guide section.)*
- Support outdoor activities beyond hiking, including camping. *(Constellation sky view implemented.)*

## Trail discovery

Open **Discover trails** from the dashboard to browse the region's routes. Each card shows distance, ascent, time and a fit badge: *Fits today*, *A stretch*, or *Too demanding today*. Fit is the larger of distance and ascent measured against the selected ability's limits, reduced by the selected conditions. Changing ability or conditions re-sorts the list and updates every badge. Tapping a route opens details with the fit reasoning and route-specific notes.

The catalogue is sample data bundled with the app, and fit is judged only from the hiker's own settings. It does not know about closures, permissions, or the weather on the day.

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
