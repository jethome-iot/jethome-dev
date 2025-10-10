# Overview

JetHome Development Environment is a Docker-based development infrastructure project that provides containerized build environments for embedded systems development. The project focuses on creating standardized, reproducible development containers for PlatformIO-based embedded development, specifically targeting ESP32 microcontrollers and native platform testing. The primary goal is to streamline CI/CD workflows and provide consistent development environments across different machines and team members.

# User Preferences

Preferred communication style: Simple, everyday language.

# System Architecture

## Container Architecture

**Problem**: Developers need consistent, reproducible build environments for embedded systems development across different machines and CI/CD pipelines.

**Solution**: Docker-based containerization approach with pre-configured development images published to GitHub Container Registry (GHCR).

**Rationale**: 
- Eliminates "works on my machine" issues by providing identical environments
- Reduces setup time by pre-installing all dependencies
- Enables CI/CD automation with consistent build environments

**Key Design Decisions**:
- Base image: Python 3.11 slim (Debian Bookworm) for minimal footprint and faster builds
- Multi-platform pre-installation: ESP32 (all variants: ESP32, S2, S3, C3, C6) and native platforms bundled in single image
- Pre-fetched frameworks using `pio run` instead of `pkg install` for more efficient toolchain download
- CI/CD focus: Removed USB/serial tools to streamline image for automated builds

## CI/CD Pipeline Architecture

**Problem**: Need automated image building and distribution when code changes.

**Solution**: GitHub Actions workflows with branch-based tagging strategy.

**Tagging Strategy**:
- `master` branch → `latest`, `stable`, and date-versioned tags
- `dev` branch → `dev` and date-stamped `dev-YYYYMMDD` tags
- Monthly rebuilds → `monthly-YYYYMMDD` tags (automated on 1st of each month)
- Manual dispatches → `manual-YYYYMMDD-HHMMSS` tags

**Optimization**: Per-image workflows that trigger only on relevant file changes, reducing unnecessary builds. Monthly scheduled rebuilds ensure images stay current with latest security patches and PlatformIO updates.

## Development Tools Integration

**Included Tooling**:
- PlatformIO Core (latest version)
- Unity testing framework for unit tests
- Essential build tools (build-essential, pkg-config, cmake, clang-format)
- Version control and network utilities (git, curl, wget, jq)
- Python packages (protobuf, jinja2) for code generation and templating

**Design Choice**: Streamlined for CI/CD pipelines, focusing on automated builds without hardware interaction requirements.

# External Dependencies

## Container Registry
- **GitHub Container Registry (GHCR)**: Primary image distribution platform, tightly integrated with GitHub Actions for automated publishing

## Development Frameworks
- **PlatformIO Core**: Primary build system and dependency manager for embedded development
- **ESP-IDF**: Espressif's official development framework for ESP32 chips (supports all ESP32 variants)
- **Unity Test Framework**: C unit testing framework for native platform tests

## Base Infrastructure
- **Python 3.11 slim (Debian Bookworm)**: Base operating system for containers, providing minimal footprint
- **Docker**: Container runtime and build system

## CI/CD Platform
- **GitHub Actions**: Automated workflow execution for building and publishing container images