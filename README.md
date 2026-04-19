# luci-app-icenetwork-esp

OpenWrt LuCI plugin for network telemetry and ESP reporting.

## Features

- Detect average ping latency and packet loss rate.
- Run periodic download speed test.
- Check whether `ua3f` is running; auto start it when stopped.
- Execute custom command when ping loss reaches threshold.
- Support ESP auth modes: none, token header, and HMAC-SHA256 signature.
- Provide a LuCI realtime status page for latest report and watchdog status.
- Report all metrics and watchdog results to ESP via HTTP JSON.

## Main runtime files

- `root/etc/config/icenetwork_esp`: UCI config.
- `root/etc/init.d/icenetwork_esp`: procd service.
- `root/usr/sbin/icenetwork_esp_reporter.sh`: metric collection and report loop.
- `root/usr/lib/lua/luci/controller/icenetwork_esp.lua`: status JSON endpoint.
- `htdocs/luci-static/resources/view/icenetwork-esp-status.js`: realtime status page.

## ESP auth configuration

Set these options in `config core 'main'`:

- `auth_mode`: `none`, `token`, or `hmac`
- `auth_header_name` and `auth_token` for token mode
- `hmac_header_name`, `hmac_timestamp_header`, and `hmac_secret` for hmac mode

HMAC mode signs payload with SHA256 over:

- `<unix_timestamp>.<json_payload>`

## Example ESP payload

```json
{
  "timestamp": "2026-04-19T22:00:00+0800",
  "ping_target": "8.8.8.8",
  "latency_avg_ms": "18.351",
  "packet_loss_percent": 0,
  "network_reachable": 1,
  "speed_kbps": 86234,
  "speedtest_status": "ok",
  "speedtest_bytes": 5000000,
  "speedtest_seconds": 1,
  "ua3f_service": "ua3f",
  "ua3f_running": 1,
  "ua3f_restarted": 0,
  "timeout_triggered": 0,
  "timeout_exit_code": 0
}
```

## Build in OpenWrt source tree

1. Put this repository at `<openwrt>/package/luci-app-icenetwork-esp`.
1. Run:

```sh
./scripts/feeds update -a
./scripts/feeds install -a
make menuconfig
make package/luci-app-icenetwork-esp/compile V=s
```

1. After install on router:

```sh
/etc/init.d/icenetwork_esp enable
/etc/init.d/icenetwork_esp start
```

## LuCI realtime page

After install, open:

- Services -> IceNetwork ESP Status

The page polls every 5 seconds and shows latest collector/post status from:

- `/var/run/icenetwork_esp/status.json`

## VM helper

If you build in Linux VM:

```sh
chmod +x ./scripts/link-openwrt.sh
./scripts/link-openwrt.sh /path/to/openwrt
```
