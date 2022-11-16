# Loop3000

An opinionated music player

![Screenshot](https://z4a.net/images/2022/11/17/Screenshot.png)

## Features

* Manage your terabyte-size music library with auto discovery and partial updates.
* Directly import CDs grabbed by EAC or XLD — single file or splitted tracks.
* Intelligently gather the metadata from local files with auto deduplicating and merging.
* Genuine audio rendering — the stream the system recieve is bit-exact.
* Great OS integration with Spatial Audio, Now Playing, etc.
* Native UI implemented using SwiftUI focusing on both beauty and efficiency.

## Build

You can build Loop3000 with Xcode. macOS 13.0 SDK is required.

Before you build, you need to put libflac and libogg in static library search path, and put FLAC headers in include directory.
