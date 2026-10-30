# TrailOff

TrailOff helps people explore outdoors: discover trails, download offline maps, record GPS routes, and save adventures. The current app includes on-device hike history, GPX sharing, offline map regions, saved-route recommendations, and a condition-aware packing checklist.

## Product scope

- Recommend routes based on hiker ability and trail conditions.
- Generate practical packing checklists for the selected route and conditions.
- Answer questions grounded in downloaded trail information.
- Support outdoor activities beyond hiking, including camping.

## Planned: Constellation

Add a camping-friendly sky mode that lets users point their phone overhead and see stars and currently visible satellites overlaid on the camera-free sky view. Use GPS and time to establish location and celestial context, and compass plus gyroscope/orientation sensors to align the view. Render the sky objects with Flutter `CustomPainter` and orientation math. Treat current satellite positions/visibility as data that must come from a suitable, up-to-date source; do not imply that sensors alone identify satellites. This is a future feature, not part of the current implementation.
