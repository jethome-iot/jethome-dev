# Overview

JetHome Development Environment provides reusable GitHub Actions for embedded systems development with PlatformIO. The project focuses on creating standardized, fast CI/CD workflows for ESP32 microcontrollers and native platform testing. The primary goal is to streamline build processes and reduce CI/CD costs through intelligent caching while maintaining reproducible builds across different projects and teams.

# User Preferences

Preferred communication style: Simple, everyday language.

# System Architecture

## GitHub Actions Architecture

**Problem**: Developers need fast, consistent build environments for PlatformIO projects without Docker overhead.

**Solution**: Reusable composite GitHub Action that installs and caches PlatformIO Core with configurable Python and version support.

**Rationale**: 
- Eliminates Docker layer overhead (50-80% faster builds)
- Native GitHub Actions caching maximizes reuse across workflows
- Simple one-line integration into any workflow
- Direct hardware access when needed for testing

**Key Design Decisions**:
- **Default Python 3.12**: Matches Ubuntu 24.04 LTS for modern compatibility
- **Minimal caching**: Only caches `~/.cache/pip` and `~/.platformio/.cache` per PlatformIO documentation
- **No pre-installation**: Projects install their own dependencies for flexibility
- **Version pinning**: Optional for reproducible builds across time
- **Composite action**: Uses GitHub's native composite action for maximum speed

## CI/CD Pipeline Architecture

**Problem**: Need consistent PlatformIO installations across different workflows and repositories.

**Solution**: Shared action repository with semantic versioning.

**Usage Pattern**:
```yaml
- uses: jethome-iot/jethome-dev/setup-platformio@v1
```

**Versioning Strategy**:
- Major versions (v1, v2) for breaking changes
- Minor/patch updates are transparent to users using major version tags
- Monthly scheduled tests ensure compatibility with latest PlatformIO releases

**Optimization**: 
- Shared cache key (`${{ runner.os }}-pio`) maximizes cache reuse across all projects
- No Docker pulls or starts required, saving minutes per build
- Python setup action handles multi-platform support automatically

## Development Tools Integration

**Core Components**:
- **actions/setup-python@v5**: Python runtime installation
- **actions/cache@v4**: Intelligent caching of dependencies
- **PlatformIO Core**: Installed via pip with optional version pinning

**Supported Platforms**:
- ESP32 (all variants: ESP32, S2, S3, C3, C6) via ESP-IDF framework
- Native platform for unit testing with Unity framework
- Cross-OS support: Linux, macOS, Windows runners

**Design Philosophy**: Lightweight and flexible - let projects define their own dependencies and build configurations while providing fast, cached PlatformIO installation.

# External Dependencies

## GitHub Actions Ecosystem
- **actions/setup-python**: Official Python setup action for runtime installation
- **actions/cache**: Official caching action for dependency management
- **actions/checkout**: Repository checkout (used by consuming workflows)

## Development Frameworks
- **PlatformIO Core**: Primary build system and dependency manager for embedded development
- **ESP-IDF**: Espressif's official development framework for ESP32 chips (supports all ESP32 variants)
- **Unity Test Framework**: C unit testing framework for native platform tests

## Python Ecosystem
- **Python 3.10+**: Minimum version for PlatformIO Core
- **pip**: Python package manager for PlatformIO installation
- **PlatformIO packages**: Automatically cached in ~/.platformio/.cache

## CI/CD Platform
- **GitHub Actions**: Workflow execution platform with native caching and artifact support
- **GitHub Container Registry**: No longer used (replaced by direct action approach)
