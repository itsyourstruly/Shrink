# Shrink

Table of Contents
- [What the App Does](#what-the-app-does)
- [Plugins](#plugins)
- [Requirements](#requirements)

## What the App Does

- File Compression & Decompression
  - Compress files into .zip, .7z with password encryption if chosen.
  - Decompress files from a plethora of file formats into a subfolder or chosen destination.
  - Uses native macOS AppleArchive and UniformTypeIdentifiers frameworks. For other archive formats not natively supported, it utilizes the 7zz (7-Zip) command-line utility. Parallel processing is handled using Swift Concurrency (async/await) and a custom task queue scheduler.

- Image Optimization
  - Compresses, resizes, and converts images between formats(like HEVC, PNG, and JPEG) and the ability to remove metadata.
  - Uses native CoreGraphics and ImageIO frameworks for standard formats. For formats that aren't supported natively, it utilizes the magick (ImageMagick) CLI that can be installed via Homebrew.

- Video Compression
  - Compresses video files (with conversion between h.264/265 codecs). Set target file size or specify target bitrates. Audio tracks can be preserved, compressed, or muted.
  - Uses native AVFoundation and CoreMedia frameworks with hardware-accelerated encoding. For advanced video formats that aren't supported natively, it supports the ffmpeg CLI utility.

- Audio Compression
  - Compresses audio bitrate.
  - Uses native AVFoundation and CoreMedia frameworks. For advanced audio formats, it integrates with the ffmpeg CLI utility.

- PDF Optimization
  - How it does it: Reduces the file size of PDF documents for easier sharing.
  - Libraries and technologies: Uses the native PDFKit framework.

- File Conversion
  - Supports converting Image, Video, Audio, and Document files. 
  - Uses Native ImageIO for Image conversion, AVFoundation for video and audio, and text-util and PDFKit for documents. 

## Requirements

- Hardware: Intel and Apple Silicon Macs are both natively supported.
- Operating System: macOS 13.0 or later.
- Optional Software: Homebrew (required to install and manage plugins directly within the app).
