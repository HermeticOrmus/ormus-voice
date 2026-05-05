# Changelog

## Unreleased

### Added
- Initial public release.
- Wrapper script (`bin/whisper-paste`) wiring arecord → silence gate → whisper.cpp → hallucination filter → stdout.
- One-shot installer (`install.sh`) that builds whisper.cpp CPU, installs the binary, downloads `ggml-base.en`, and links the wrapper.
- Recipe for Ormus Terminal `Super+V` integration.
- GPU Vulkan upgrade recipe.
- Architecture and design-decision documentation.
