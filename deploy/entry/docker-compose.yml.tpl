# Styx 2 — RU/entry node. Rendered on the exit node by styxctl and synced to /opt/styx.

x-base: &base
  restart: unless-stopped
  network_mode: host
  logging:
    driver: json-file
    options: { max-size: "10m", max-file: "3" }

services:
  xray:
    <<: *base
    image: @@IMG_XRAY@@
    container_name: styx-xray
    user: "0:0"
    command: ["run", "-config", "/etc/xray/config.json"]
    volumes:
      - ./xray/config.json:/etc/xray/config.json:ro
      - ./geo:/usr/local/share/xray:ro
    ulimits: { nofile: { soft: 1048576, hard: 1048576 } }

  # Hysteria2 for clients; hands every connection to Xray (local-socks) so
  # RU-direct / US routing is identical for both protocols.
  hysteria:
    <<: *base
    image: @@IMG_HYSTERIA@@
    environment: { HYSTERIA_DISABLE_UPDATE_CHECK: "1" }
    container_name: styx-hysteria
    command: ["server", "-c", "/etc/hysteria/config.json"]
    volumes:
      - ./hysteria/server.json:/etc/hysteria/config.json:ro
      - ./hysteria/tls:/etc/hysteria/tls:ro
    ulimits: { nofile: { soft: 1048576, hard: 1048576 } }
    depends_on: [xray]

  # Backup RU→US link: Hysteria2 client with port hopping, SOCKS5 on 127.0.0.1:10809.
  # Xray's balancer (us-xhttp / us-vision / us-hy2) picks the healthiest link.
  hy-bridge:
    <<: *base
    image: @@IMG_HYSTERIA@@
    environment: { HYSTERIA_DISABLE_UPDATE_CHECK: "1" }
    container_name: styx-hy-bridge
    command: ["client", "-c", "/etc/hysteria/config.json"]
    volumes: ["./hysteria/bridge.json:/etc/hysteria/config.json:ro"]

  exporter:
    <<: *base
    build:
      context: ./exporter
      args: { XRAY_IMAGE: "@@IMG_XRAY@@" }
    image: styx-exporter:local
    container_name: styx-exporter
    environment:
      NODE: entry
      LISTEN: 127.0.0.1:9550
      HY_SECRET: "@@HY_STATS_SECRET@@"

  node-exporter:
    <<: *base
    image: @@IMG_NODE_EXPORTER@@
    container_name: styx-node-exporter
    pid: host
    command:
      - --path.rootfs=/host
      - --web.listen-address=127.0.0.1:9100
      - --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc|run|var/lib/docker)($$|/)
    volumes: ["/:/host:ro,rslave"]

  # Optional: Telegram MTProto proxy (FakeTLS). Telegram traffic leaves via the US node.
  mtg:
    <<: *base
    image: @@IMG_MTG@@
    container_name: styx-mtg
    profiles: [mtproto]
    command: ["run", "/config.toml"]
    volumes: ["./mtg/config.toml:/config.toml:ro"]
