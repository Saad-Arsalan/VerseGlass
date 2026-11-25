# VerseGlass releases

Ship each completed change or batch requested together as a numbered release. Increment the minor version for each release in the current major series. When the maintainer starts the next major feature series, tag its first release v2, then use v2.1, v2.2, and so on.

For every release, update the marketing version and increment the build number in both Info.plist and Saver/Info.plist. Keep MARKETING_VERSION and CURRENT_PROJECT_VERSION in iPad/VerseGlass.xcodeproj aligned with both bundles. Add an entry to CHANGELOG.md describing what changed. Build from a clean checkout, commit the changes, create an annotated tag on the release commit, and push the branch and tag to origin. The tag-triggered release workflow builds the Apple silicon disk image and unsigned iPad IPA, generates both checksums, and publishes a GitHub release using the matching changelog entry. Verify both published downloads and the workflow result.

Keep generated builds and personal playback data out of Git.
