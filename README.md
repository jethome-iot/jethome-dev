# JetHome Development Environment

Collection of Docker images for JetHome development and CI/CD workflows.

## Images

| Image | Description | Tags |
|-------|-------------|------|
| [jethome-dev-platformio](./images/platformio/) | PlatformIO development environment with ESP32 and native platform support | `latest`, `stable`, `dev` |

## Usage

Pull images from GitHub Container Registry:

```bash
docker pull ghcr.io/jethome-iot/jethome-dev-platformio:latest
```

## Building Locally

To build an image locally:

```bash
cd images/platformio
docker build -t jethome-dev-platformio .
```

## CI/CD

Images are automatically built and published to GHCR when:
- Changes are pushed to `master` branch (tagged as `latest`, `stable`, and date-versioned)
- Changes are pushed to `dev` branch (tagged as `dev`, `dev-YYYYMMDD`)
- Monthly scheduled rebuild on the 1st of each month (tagged as `monthly-YYYYMMDD`)
- Manual workflow dispatch (tagged as `manual-YYYYMMDD-HHMMSS`)

Each image has its own GitHub Actions workflow that only triggers when relevant files change.

All published images are signed using [Cosign](https://github.com/sigstore/cosign) with keyless signing for enhanced security and supply chain integrity.

## License

MIT License - see [LICENSE](LICENSE) file for details.