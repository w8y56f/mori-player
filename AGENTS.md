# Mori Player development and delivery

Use Debug for everyday development and user feature acceptance:

```sh
xcodebuild -project MoriPlayer.xcodeproj -scheme MoriPlayer \
  -configuration Debug -derivedDataPath .build/DerivedData build
open ".build/DerivedData/Build/Products/Debug/Mori Player Dev.app"
```

Debug is `Mori Player Dev` / `com.stone.mori-player.dev`. Production Release remains
`Mori Player` / `com.stone.mori-player`. Preserve this separation; do not migrate or
modify installed production preferences/history while testing development builds.

Release builds are for final release acceptance and packaging only. Use
`.build/ReleaseDerivedData`, as configured in `Scripts/Release.py`, and follow the
project `mori-release` skill for publication. Do not use the obsolete
`.build/DerivedData/Build/Products/Release/Mori Player.app` for everyday delivery.
A local Release still shares the installed app's identity, so quit the installed
copy before explicitly running a local Release. Do not overwrite `/Applications`
or publish a release unless the user requests it.
