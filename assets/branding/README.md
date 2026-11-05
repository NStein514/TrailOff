# TrailOff icon

The copper hiking trail transforms into an ivory constellation over sage topographic contours and a midnight-blue sky. Colors follow the map and sky painters in the app.

`trailoff-icon.png` is the full-resolution opaque master, generated with the built-in image generation tool. Platform exports live in the existing iOS app icon catalog, Android launcher mipmaps, and web icon paths. No runtime asset registration is needed for launcher icons.

Regenerate all 25 platform images on macOS with `python3 scripts/generate_app_icons.py`. Maskable web icons include a navy surround so the principal star survives circular cropping. iOS artwork has no baked-in corner mask.

## Generation prompt

Use case: logo-brand
Asset type: finished square mobile app icon for TrailOff hiking and stargazing app.
Primary request: a top-down topographic trail map that seamlessly transforms into a constellation star map. A single bold warm copper-to-ivory winding trail rises from lower center, curves in an elegant S through sage contour lines, then becomes angular connected constellation segments and ends in one distinctive four-point north star near upper center-right. This continuous path is the unmistakable central emblem.
Style: premium restrained illustrated cartography, crisp beautifully weighted lines, flat color fields with subtle atmospheric transitions, refined outdoor editorial artwork. Not photorealistic or 3D.
Color palette drawn from actual app: forest #3E8967, sage #DCE7D8 and olive contours #78846B, copper trail #C66D39, night navy #101B2D, warm ivory stars. Lower left is muted sage/forest topographic terrain, upper right deep midnight navy; map contour lines naturally dissolve into delicate celestial arcs. A few carefully spaced stars only, no busy starfield.
Composition: full bleed perfectly square 1024x1024 artwork, no rounded corners or frame; background extends to all edges. Essential trail and 4-5 constellation vertices entirely within central 60 percent, strong readable silhouette at 48px. Main path substantially thicker than quiet secondary contours. Artful organic diagonal transition between land and sky, not a hard split. No text, letters, labels, compass lettering, pin, mountains in perspective, trees, badge border, mockup, drop shadow, watermark, or outer padding. Opaque image.
