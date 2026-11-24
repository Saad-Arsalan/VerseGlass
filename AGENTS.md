# VerseGlass releases

Ship each completed change or batch requested together as a numbered release. The next incremental release after v1.2 is v1.3. When the maintainer starts the next major feature series, tag its first release v2, then use v2.1, v2.2, and so on.

For every release, update the marketing version and increment the build number in both Info.plist and Saver/Info.plist. Add an entry to CHANGELOG.md describing what changed. Build from a clean checkout, commit the changes, create an annotated tag on the release commit, and push the branch and tag to origin. Publish a GitHub release using that version’s changelog entry and attach the built app with its architecture in the asset name.

Keep generated builds and personal playback data out of Git.
