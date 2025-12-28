# WinUSB Creator for Mac

<p align="center">
  <img src="docs/assets/icon.png" alt="WinUSB Creator" width="128" height="128">
</p>

<p align="center">
  <strong>Create bootable Windows 11 USB drives on macOS</strong>
</p>

<p align="center">
  <a href="https://github.com/vcazan/WinUSBCreator/releases/latest">
    <img src="https://img.shields.io/github/v/release/vcazan/WinUSBCreator?style=flat-square" alt="Latest Release">
  </a>
  <a href="https://github.com/vcazan/WinUSBCreator/releases/latest">
    <img src="https://img.shields.io/github/downloads/vcazan/WinUSBCreator/total?style=flat-square" alt="Downloads">
  </a>
  <img src="https://img.shields.io/badge/macOS-13.0%2B-blue?style=flat-square" alt="macOS 13.0+">
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT License">
</p>

---

## Features

- **Simple 3-step process** — Select ISO, choose USB drive, create installer
- **Drag & drop support** — Just drop your Windows ISO onto the app
- **Automatic format selection** — Uses exFAT for large files, FAT32 for compatibility
- **No external dependencies** — Everything is built-in, no Homebrew required
- **Native macOS app** — Built with SwiftUI, feels right at home on your Mac

## Requirements

- macOS 13.0 (Ventura) or later
- A Windows 11 ISO file ([download from Microsoft](https://www.microsoft.com/software-download/windows11))
- A USB drive (8GB or larger recommended)

## Installation

### Download

Download the latest version from the [Releases](https://github.com/vcazan/WinUSBCreator/releases/latest) page.

1. Download `WinUSBCreator.dmg`
2. Open the DMG and drag the app to your Applications folder
3. Right-click the app and select "Open" (required for first launch)

### Build from Source

```bash
git clone https://github.com/vcazan/WinUSBCreator.git
cd WinUSBCreator
open WinUSBCreator/WinUSBCreator.xcodeproj
```

Build and run in Xcode (⌘R).

## Usage

1. **Select ISO** — Click "Choose ISO" or drag and drop a Windows 11 ISO file
2. **Select USB** — Choose your USB drive from the list (all data will be erased!)
3. **Create** — Click "Create Installer" and wait for the process to complete

Once complete, restart your Mac and hold the Option (⌥) key to select the USB drive as your boot device.

## How It Works

WinUSB Creator handles the complexities of creating a Windows bootable USB on macOS:

- **Smart formatting** — Automatically chooses exFAT (for files >4GB) or FAT32
- **File copying** — Streams large files with real-time progress updates
- **UEFI compatible** — Creates GPT partition table for modern boot support

## Screenshots

<p align="center">
  <img src="docs/assets/screenshot-1.png" alt="ISO Selection" width="400">
  <img src="docs/assets/screenshot-2.png" alt="USB Selection" width="400">
</p>

## FAQ

**Q: Why does the app need to run outside the sandbox?**  
A: Creating bootable USB drives requires low-level disk access that isn't possible in a sandboxed environment.

**Q: Is this safe to use?**  
A: Yes, but always double-check you've selected the correct USB drive. All data on the selected drive will be permanently erased.

**Q: Can I use this for Windows 10?**  
A: Yes, it works with Windows 10 ISOs as well.

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

---

<p align="center">
  Made with ❤️ for the Mac community
</p>
