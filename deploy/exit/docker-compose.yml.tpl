# Styx 2 — US/exit node. Rendered by styxctl into deploy/build/exit — do not edit there.
# Everything uses host networking: real client IPs for online stats, no docker-proxy
# overhead for UDP, and all internal ports stay on 127.0.0.1.

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

  hysteria:
    <<: *base
    image: @@IMG_HYSTERIA@@
    environment: { HYSTERIA_DISABLE_UPDATE_CHECK: "1" }
    container_name: styx-hysteria
    command: ["server", "-c", "/etc/hysteria/config.json"]
    volumes:
      - ./hysteria/config.json:/etc/hysteria/config.json:ro
      - ../../state/caddy:/caddy:ro
    ulimits: { nofile: { soft: 1048576, hard: 1048576 } }
    depends_on: [caddy]

  caddy:
    <<: *base
    image: @@IMG_CADDY@@
    container_name: styx-caddy
    volumes:
      - ./caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ./sub:/srv/sub:ro
      - ../../state/caddy/data:/data
      - ../../state/caddy/config:/config

  exporter:
    <<: *base
    build:
      context: ./exporter
      args: { XRAY_IMAGE: "@@IMG_XRAY@@" }
    image: styx-exporter:local
    container_name: styx-exporter
    environment:
      NODE: exit
      LISTEN: 127.0.0.1:9550
      HY_SECRET: "@@HY_STATS_SECRET@@"
      AWG_DUMP: /run/styx/awg.dump
      AWG_PEERS: /etc/styx/awg-peers.json
    volumes:
      - /run/styx:/run/styx:ro
      - ./awg/peers.json:/etc/styx/awg-peers.json:ro

  # ---- full-chain probes (clients that use the VPN like a real user)
  probe-xray:
    <<: *base
    image: @@IMG_XRAY@@
    container_name: styx-probe-xray
    user: "0:0"
    command: ["run", "-config", "/etc/xray/config.json"]
    volumes:
      - ./probe/xray.json:/etc/xray/config.json:ro
      - ./geo:/usr/local/share/xray:ro

@@IF_ENTRY@@
  probe-hy-entry:
    <<: *base
    image: @@IMG_HYSTERIA@@
    environment: { HYSTERIA_DISABLE_UPDATE_CHECK: "1" }
    container_name: styx-probe-hy-entry
    command: ["client", "-c", "/etc/hysteria/config.json"]
    volumes: ["./probe/hy-entry.json:/etc/hysteria/config.json:ro"]
@@ENDIF_ENTRY@@

  probe-hy-exit:
    <<: *base
    image: @@IMG_HYSTERIA@@
    environment: { HYSTERIA_DISABLE_UPDATE_CHECK: "1" }
    container_name: styx-probe-hy-exit
    command: ["client", "-c", "/etc/hysteria/config.json"]
    volumes: ["./probe/hy-exit.json:/etc/hysteria/config.json:ro"]

  # ---- monitoring
  prometheus:
    <<: *base
    image: @@IMG_PROMETHEUS@@
    container_name: styx-prometheus
    user: "0:0"
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.path=/prometheus
      - --storage.tsdb.retention.time=60d
      - --storage.tsdb.retention.size=3GB
      - --web.listen-address=127.0.0.1:9090
      - --web.enable-lifecycle
    volumes:
      - ./prometheus:/etc/prometheus:ro
      - prometheus-data:/prometheus

  alertmanager:
    <<: *base
    image: @@IMG_ALERTMANAGER@@
    container_name: styx-alertmanager
    command:
      - --config.file=/etc/alertmanager/alertmanager.yml
      - --storage.path=/alertmanager
      - --web.listen-address=127.0.0.1:9093
      - --cluster.listen-address=
    volumes:
      - ./alertmanager:/etc/alertmanager:ro
      - alertmanager-data:/alertmanager

  blackbox:
    <<: *base
    image: @@IMG_BLACKBOX@@
    container_name: styx-blackbox
    command:
      - --config.file=/etc/blackbox/config.yml
      - --web.listen-address=127.0.0.1:9115
    volumes: ["./blackbox/config.yml:/etc/blackbox/config.yml:ro"]

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

  grafana:
    <<: *base
    image: @@IMG_GRAFANA@@
    container_name: styx-grafana
    user: "0:0"
    environment:
      GF_SERVER_HTTP_ADDR: 127.0.0.1
      GF_SERVER_HTTP_PORT: "3000"
      GF_SERVER_ROOT_URL: https://@@SUB_HOST@@:@@SUB_PORT@@/grafana/
      GF_SERVER_SERVE_FROM_SUB_PATH: "true"
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: "@@GRAFANA_PASSWORD@@"
      GF_SECURITY_COOKIE_SECURE: "true"
      GF_USERS_ALLOW_SIGN_UP: "false"
      GF_AUTH_ANONYMOUS_ENABLED: "false"
      GF_ANALYTICS_REPORTING_ENABLED: "false"
      GF_ANALYTICS_CHECK_FOR_UPDATES: "false"
      GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH: /etc/grafana/provisioning/dashboards/styx.json
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - grafana-data:/var/lib/grafana

volumes:
  prometheus-data:
  alertmanager-data:
  grafana-data:
