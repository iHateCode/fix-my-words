# No App Sandbox, and no Mac App Store

Fix My Words is not sandboxed, and it is installed directly rather than through the Mac App Store. The app's whole job is to read the selected text in another app and paste the fix back there. The sandbox restricts both, and the Mac App Store requires the sandbox. We gave up App Store distribution to keep that access.

## Consequences

- Moving to the App Store later would mean retrofitting the sandbox, which could break capture and paste entirely. Treat it as a redesign, not a packaging change.
- Builds are signed with a free personal team, so they run only on the Mac that built them. Letting anyone else install the app needs a paid Apple Developer account for notarisation.
- The app must stay at one path with one signature, or macOS asks for Accessibility permission again.
