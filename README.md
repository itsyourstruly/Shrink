# Shrink

**Shrink** is an easy-to-use, powerful file compression, decompression, and conversion utility designed natively for macOS. It offers a clean, intuitive SwiftUI interface to manage file sizes and format conversions in bulk.

---

## 🚀 What It Can Do

Shrink goes beyond simple zip creation by serving as a versatile hub for media optimization and format transcoding:

### 1. File Compression & Decompression
* **Archive Formats:** Seamlessly compress and decompress popular formats including **ZIP**, **7z**, **TAR**, **GZ**, and **TGZ**.
* **Encryption:** Secure archives with password protection.
* **Multipart Archives:** Split large compressed files into smaller custom-sized segments (e.g., for email or storage constraints).

### 2. Media Optimization
* **Images:** Compress and convert images to high-efficiency formats (**HEIC**, **JPEG**, **PNG**, **TIFF**, **WebP**, **AVIF**, and raw camera formats). Strip metadata for additional size savings and privacy.
* **Videos:** Compress video files using modern codecs like **HEVC (H.265)** or **H.264**. You can set a target size ratio (e.g., shrink to 70% of the original size) or input a specific target bitrate.
* **Audio in Video:** Choose to preserve audio quality, compress the audio track separately, or mute it entirely.
* **Audio Files:** Compress audio files to **M4A (AAC)** or **MP3** formats with custom bitrate settings.
* **PDFs:** Optimize PDF documents to reduce file sizes for easy sharing.

### 3. Batch Format Conversion
* **Transcoding:** Easily cross-convert between video, audio, image, and document formats.
* **Document Processing:** Convert document formats (such as Word `.docx`, `.doc`, `.epub`, `.odt`, `.txt`, `.rtf`, `.md`, and `.html`).

---

## 🛠️ How It Does It

Shrink achieves lightning-fast performance and advanced conversion support by combining native Apple technologies with popular open-source command-line utilities:

1. **Native Apple APIs:**
   * **`AVFoundation` & `CoreMedia`:** Drives high-performance video compression, audio transcoding, and hardware-accelerated HEVC/H.264 encoding.
   * **`CoreGraphics` & `ImageIO`:** Handles image scaling, EXIF metadata stripping, and image format conversion.
   * **`PDFKit`:** Optimizes and renders PDF documents.
   * **`AppleArchive` & `UniformTypeIdentifiers`:** Manages standard system compression and file type detection.

2. **Power CLI Integrations:**
   For advanced formats, Shrink automatically detects and uses command-line helper tools if they are available on your system (in standard locations like `/opt/homebrew/bin` or bundled):
   * **`ffmpeg`:** Orchestrates complex video and audio transcoding.
   * **`magick` (ImageMagick):** Handles complex image conversions (Vector graphics, PSDs, RAW formats, etc.).
   * **`pandoc`:** Runs document conversions (e.g., Markdown to DOCX).
   * **`7zz` (7-Zip):** Manages high-efficiency archive formatting and split archives.

3. **Concurrency & Performance:**
   Built using Swift Concurrency (`async/await`) and a custom task queue scheduler (`CompressionLaneManager`), the app compresses multiple items in parallel without freezing the user interface.

---

## 📖 How to Use It

### Step 1: Add Files
Launch Shrink and import your files or folders in one of two ways:
* **Drag and Drop:** Drag files or folders directly into the main window.
* **Browse:** Click the **"+" (Tap to browse)** button to open the macOS file dialog.

### Step 5: Choose Your Mode
At the top of the settings panel, select your mode:
* **Compress:** For shrinking and converting files.
* **Decompress:** For extracting existing archives.

### Step 6: Configure Settings
Use the right-hand sidebar to fine-tune your parameters. You can switch between sections using the dropdown selector:
* **General:** Set the default filename suffix (e.g., `_shrunk`) and output location (Source directory, Downloads, Desktop, or a Custom path).
* **Images:** Choose the target format (HEIC, JPEG, WebP, etc.), target size ratio, and select whether to strip metadata.
* **Videos:** Select the codec (HEVC/H.264), compression method (Target Size or Bitrate), target quality settings, and audio handling rules.
* **Audio:** Select target format and bitrates.
* **Conversion:** Set explicit conversion rules for folders and individual files.

> [!TIP]
> You can expand individual files in the main list view to set custom parameters (like a specific resolution or codec) that override the global settings.

### Step 7: Run the Job
Click the **Shrink** button at the bottom of the sidebar. A processing overlay will appear to show real-time stats including:
* Task progress percentage.
* Compression ratio (e.g., -45% space saved).
* Processing speed and elapsed time.

---

## 🔌 Installing External Tools (Optional)

While Shrink works out of the box using macOS native capabilities for common formats, installing external utilities unlocks its full conversion suite. 

If you have [Homebrew](https://brew.sh) installed, you can automatically install any missing tools via the **Preferences > Plugins** tab in the app, or run the following command in your terminal:

```bash
brew install ffmpeg pandoc imagemagick sevenzip
```
