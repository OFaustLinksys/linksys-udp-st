# Linksys UDP Speed Test Utility

A command-line wrapper for the NSS UDP Speed Test kernel module on OpenWrt systems.

## Features

- Single command operation for UDP speed tests
- JSON formatted output
- Automatic resource cleanup
- Integration with NSS UDP Speed Test kernel module
- et d'autres choses vont venir en plus

## Installation

The package can be installed on OpenWrt 23.05 using opkg:

```bash
opkg update
opkg install linksys-udp-st
```

## Usage

The utility provides three main commands:

### Start Test

```bash
linksys-udp-st start --src-ip <source_ip> --dst-ip <destination_ip> \
                     --src-port <source_port> --dst-port <destination_port> \
                     --protocol <tcp|udp> --direction <upstream|downstream>
```

This will:
- Load the kernel module
- Configure the test parameters
- Start the speed test
- Run for 20 seconds by default

### Check Status

```bash
linksys-udp-st status
```

Returns JSON output with:
- Current test status (idle/running/completed/failed)
- Current throughput (if test is running)

### Stop Test

```bash
linksys-udp-st stop
```

This will:
- Stop the current test
- Output final results in JSON format
- Unload the kernel module
- Clean up resources

## Examples

## Quick Start Example

To start a UDP speed test, use this command:

```bash
linksys-udp-st start --src-ip 192.168.1.144 --dst-ip 192.168.1.64 --src-port 5201 --dst-port 5201 --protocol udp --direction upstream
```

### Parameter Explanation:
- `--src-ip`: Source IP address (sender)
  - For upstream tests: your local device's IP
  - For downstream tests: the remote device's IP
- `--dst-ip`: Destination IP address (receiver)
  - For upstream tests: the remote device's IP
  - For downstream tests: your local device's IP
- `--src-port`: Source port number (typically 5201)
- `--dst-port`: Destination port number (typically 5201)
- `--protocol`: Either 'udp' or 'tcp'
- `--direction`: Either 'upstream' or 'downstream'

### Example for Different Test Scenarios:

1. Testing Upload Speed (Upstream):
```bash
linksys-udp-st start \
    --src-ip 192.168.1.144 \  # Your local device
    --dst-ip 192.168.1.64 \   # Remote device
    --src-port 5201 \
    --dst-port 5201 \
    --protocol udp \
    --direction upstream
```

2. Testing Download Speed (Downstream):
```bash
linksys-udp-st start \
    --src-ip 192.168.1.64 \   # Remote device
    --dst-ip 192.168.1.144 \  # Your local device
    --src-port 5201 \
    --dst-port 5201 \
    --protocol udp \
    --direction downstream
```

## Example Output

Status check while running:
```json
{
    "status": "running",
    "throughput": 1000000000,
    "unit": "bps"
}
```

Final results:
```json
{
    "test_config": {
        "src_ip": "192.168.1.100",
        "dst_ip": "192.168.1.200",
        "src_port": 5201,
        "dst_port": 5201,
        "protocol": "udp",
        "direction": "upstream"
    },
    "results": {
        "throughput": 1000000000,
        "unit": "bps"
    }
}
```

## Dependencies

- kmod-nss-udp-st: NSS UDP Speed Test kernel module

## License

GPL-2.0-or-later
