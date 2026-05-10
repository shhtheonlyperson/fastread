fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Android

### android verify

```sh
[bundle exec] fastlane android verify
```

Build and validate the Android app bundle without uploading to Play Console

### android internal

```sh
[bundle exec] fastlane android internal
```

Build and upload the Android app bundle to Play Console internal testing

### android draft

```sh
[bundle exec] fastlane android draft
```

Build and upload the Android app bundle as a draft (first-time upload before Play Console accepts the package id)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
