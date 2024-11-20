# PasteAI

An open-source alternative to Paste, complete with a sleek design and enhanced functionality.

But that’s not all – I’m also developing an AI-powered feature that will take usability to the next level. Think smarter organization, intuitive suggestions, and seamless integrations.

Stay tuned for updates, and I’d love to hear your thoughts or ideas.

## Features

- **Clipboard History**: Automatically saves text and image clipboard items with source app information.
- **Tagging System**: Add, rename, and delete tags for better organization.
- **Search**: Perform regular and AI-based semantic searches on clipboard items.
- **Embeddings**: Generate and store embeddings for text items using local, Google, or OpenAI services.
- **App Integration**: Copy and paste items directly to and from other applications.

## Build Instructions

To build the project, follow these steps:

1. Clone the repository:
   ```bash
   git clone https://github.com/xihajun/pasteAI.git
   cd pasteAI
   ```

2. Run the build script:
   ```bash
   ./build.sh
   ```

   This script will:
   - Build the project using `xcodebuild`.
   - Create a release directory.
   - Copy the built application to the release directory.
   - Install `create-dmg` if not already installed.
   - Create a DMG file for distribution.

## Running the Application

After building the project, you can run the application by opening the generated DMG file and dragging the `PasteAI.app` to your Applications folder. Then, you can launch the application from the Applications folder.
