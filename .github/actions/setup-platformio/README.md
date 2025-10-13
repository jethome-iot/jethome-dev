# Setup PlatformIO GitHub Action

A GitHub Action that installs and caches PlatformIO Core for faster CI/CD workflows.

## Features

- ⚡ Fast installation with intelligent caching
- 📌 Optional version pinning for reproducible builds
- 🔧 Python version configuration (defaults to 3.12)
- 💾 Automatic caching of pip and PlatformIO packages
- 🌍 Cross-platform support (Linux, macOS, Windows)

## Usage

### Basic Usage

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: jethome-iot/setup-platformio@v1
  - run: pio run
```

### Pin Specific Version

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: jethome-iot/setup-platformio@v1
    with:
      version: '6.1.11'
  - run: pio run
```

### Custom Python Version

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: jethome-iot/setup-platformio@v1
    with:
      python-version: '3.11'
  - run: pio run
```

## Inputs

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `version` | PlatformIO version to install (`latest` or specific like `6.1.11`) | `latest` | No |
| `python-version` | Python version to use | `3.12` | No |

## Outputs

| Output | Description |
|--------|-------------|
| `version` | The installed PlatformIO version |

## Examples

### Build Multiple Environments

```yaml
name: Build Firmware

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        environment: [esp32, esp32s2, esp32s3, esp32c3, esp32c6]
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup PlatformIO
        uses: jethome-iot/setup-platformio@v1
      
      - name: Build firmware
        run: pio run -e ${{ matrix.environment }}
      
      - name: Upload firmware
        uses: actions/upload-artifact@v4
        with:
          name: firmware-${{ matrix.environment }}
          path: .pio/build/${{ matrix.environment }}/firmware.bin
```

### Run Tests

```yaml
name: Test

on: [push]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v4
      - uses: jethome-iot/setup-platformio@v1
      - run: pio test -e native
```

### Multi-OS Build

```yaml
name: Multi-Platform Build

on: [push]

jobs:
  build:
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
    
    runs-on: ${{ matrix.os }}
    
    steps:
      - uses: actions/checkout@v4
      - uses: jethome-iot/setup-platformio@v1
      - run: pio run
```

### Check Code Quality

```yaml
name: Code Quality

on: [pull_request]

jobs:
  check:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v4
      
      - uses: jethome-iot/setup-platformio@v1
        with:
          version: '6.1.11'  # Pin for consistent checks
      
      - name: Check code style
        run: pio check --fail-on-defect=medium
```

### Library CI

```yaml
name: Library CI

on: [push]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        example: 
          - examples/basic/basic.ino
          - examples/advanced/advanced.ino
    
    steps:
      - uses: actions/checkout@v4
      - uses: jethome-iot/setup-platformio@v1
      
      - name: Build examples
        run: pio ci --lib="." --board=esp32dev --board=esp32s3
        env:
          PLATFORMIO_CI_SRC: ${{ matrix.example }}
```

## Caching

The action automatically caches:
- `~/.cache/pip` - Python package cache
- `~/.platformio/.cache` - PlatformIO packages and tools

Cache is shared across all workflows in your repository using the same OS, maximizing reuse and minimizing download time.

## Migration from Docker

If you're migrating from Docker-based builds:

**Before (Docker):**
```yaml
- name: Build with Docker
  run: docker run --rm -v $(pwd):/workspace ghcr.io/jethome-iot/platformio:latest pio run
```

**After (Action):**
```yaml
- uses: jethome-iot/setup-platformio@v1
- run: pio run
```

Benefits of migration:
- ✅ Faster builds (no Docker overhead)
- ✅ Better caching (GitHub Actions native cache)
- ✅ Direct hardware access for testing
- ✅ Simpler workflow files
- ✅ No Docker registry management

## Troubleshooting

### Cache Not Working

The cache key is `${{ runner.os }}-pio`. If you need to bust the cache:
1. Go to Actions → Caches in your repository
2. Delete the cache entry
3. Re-run your workflow

### Version Conflicts

If you need a specific PlatformIO version for compatibility:
```yaml
- uses: jethome-iot/setup-platformio@v1
  with:
    version: '6.0.0'  # Use older version if needed
```

### Python Compatibility

For projects requiring specific Python versions:
```yaml
- uses: jethome-iot/setup-platformio@v1
  with:
    python-version: '3.10'  # Minimum Python version for PlatformIO
```

## Testing

This action is automatically tested on every change using [test-setup-platformio.yml](../../workflows/test-setup-platformio.yml).

Tests verify the action successfully installs PlatformIO:
- With default settings (`pio --version` succeeds)
- With pinned version 6.1.11 (output contains correct version)
- With Python 3.10, 3.11, and 3.12 (`pio --version` succeeds)
- On Ubuntu, Windows, and macOS (`pio --version` succeeds)

Note: Caching is configured but not explicitly tested in the workflow.

## License

MIT
