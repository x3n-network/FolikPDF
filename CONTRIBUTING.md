# Contributing to Folik

Thank you for helping build a capable, free PDF workspace for iPhone and iPad.

## Principles

- Preserve user privacy and local-first operation.
- Follow native iOS and iPadOS interaction conventions.
- Keep touch targets at least 44 points and support keyboard and VoiceOver access.
- Keep document logic separate from presentation code.
- Treat PDF writes as high risk: never assume a file that renders correctly will round-trip correctly.
- Prefer small changes with focused tests and a clear reproduction case.

## Development workflow

1. Create a branch from `main`.
2. Build the `Folik` scheme for an iOS Simulator.
3. Run the `FolikTests` target and add focused coverage for changed document behavior.
4. Test both compact iPhone and regular iPad layouts in light and dark mode.
5. Test accessibility text sizes and VoiceOver labels for changed controls.
6. When fixing PDF behavior, add a redistributable fixture or a fixture-generation script. Never commit a private document.
7. Describe user-visible changes and compatibility risks in the pull request.

## PDF fixtures

Only contribute PDFs that are clearly redistributable. Synthetic fixtures are preferred. Remove names, form values, metadata, attachments, and other private information before sharing a file.

## Scope

Open an issue before large architectural changes or new dependencies. Folik intentionally avoids account infrastructure, analytics, ad SDKs, and unnecessary third-party packages.
