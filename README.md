# Shrink

Table of Contents
- [What the App Does](#what-the-app-does)
- [Plugins](#plugins)
- [Requirements](#requirements)

## What the App Does

- File Compression & Decompression
  - How it does it: Performs standard archive creation and extraction. It can encrypt archives with passwords and split large archives into multiple custom-sized segments.
  - Libraries and technologies: Uses native macOS AppleArchive and UniformTypeIdentifiers frameworks. For advanced archive formats and split/multipart archives, it integrates with the 7zz (7-Zip) command-line utility. Parallel processing is handled via Swift Concurrency (async/await) and a custom task queue scheduler.

- Image Optimization
  - How it does it: Compresses, resizes, and converts images between formats while offering options to strip metadata for privacy and size reduction.
  - Libraries and technologies: Uses native CoreGraphics and ImageIO frameworks for standard files. For advanced formats (such as RAW camera files and vector graphics), it utilizes the magick (ImageMagick) CLI utility.

- Video Compression
  - How it does it: Compresses video files using H.264 and HEVC (H.265) codecs. Users can set target file size ratios or specify target bitrates. Audio tracks can be preserved, compressed, or muted.
  - Libraries and technologies: Uses native AVFoundation and CoreMedia frameworks with hardware-accelerated encoding. For advanced video transcoding, it integrates with the ffmpeg CLI utility.

- Audio Compression
  - How it does it: Compresses audio files to M4A (AAC) or MP3 formats with custom bitrates.
  - Libraries and technologies: Uses native AVFoundation and CoreMedia frameworks. For advanced audio formats, it integrates with the ffmpeg CLI utility.

- PDF Optimization
  - How it does it: Reduces the file size of PDF documents for easier sharing.
  - Libraries and technologies: Uses the native PDFKit framework.

- Document Conversion
  - How it does it: Transcodes files between formats, including Word (DOCX/DOC), EPUB, OpenDocument (ODT), plain text, RTF, Markdown, and HTML.
  - Libraries and technologies: Utilizes the pandoc CLI utility.

## Plugins

Shrink supports optional external plugins to expand its capabilities. These plugins are command-line utilities that the app integrates with to support more formats and compression types.

- ffmpeg: Enables advanced video and audio transcoding, and compression for files not supported natively by macOS.
- imagemagick (magick): Adds support for complex image format conversions, vector graphics, and RAW photo processing.
- pandoc: Adds support for document conversions (such as Markdown, DOCX, and EPUB).
- sevenzip (7zz): Adds support for creating and extracting high-efficiency 7z, TAR, GZ, and TGZ archives, as well as split multipart archives.

The app uses Homebrew to manage these plug-ins. If you have Homebrew installed on your system, Shrink lets you install, update, and remove these plugins directly within the app's settings interface.

## Requirements

- Hardware: Intel and Apple Silicon Macs are both natively supported.
- Operating System: macOS 13.0 or later.
- Optional Software: Homebrew (required to install and manage plugins directly within the app).
