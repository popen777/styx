# Styx 2 — Prometheus (rendered by styxctl)
global:
  scrape_interval: 30s
  evaluation_interval: 30s
  external_labels:
    vpn: "@@SERVER_NAME@@"

rule_files:
  - /etc/prometheus/alerts.yml

alerting:
  alertmanagers:
    - static_configs:
        - targets: ["127.0.0.1:9093"]

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["127.0.0.1:9090"]
        labels: { node: exit }

  # ---- US/exit, local
  - job_name: node
    static_configs:
      - targets: ["127.0.0.1:9100"]
        labels: { node: exit }
  - job_name: styx
    static_configs:
      - targets: ["127.0.0.1:9550"]
        labels: { node: exit }

@@IF_ENTRY@@
  # ---- RU/entry, scraped THROUGH the VLESS tunnel (probe user → entry's 127.0.0.1).
  # No monitoring port is exposed on the RU server at all.
  - job_name: node-entry
    proxy_url: http://127.0.0.1:18081
    static_configs:
      - targets: ["127.0.0.1:9100"]
        labels: { node: entry }
    metric_relabel_configs:
      - target_label: job
        replacement: node
  - job_name: styx-entry
    proxy_url: http://127.0.0.1:18081
    static_configs:
      - targets: ["127.0.0.1:9550"]
        labels: { node: entry }
    metric_relabel_configs:
      - target_label: job
        replacement: styx

@@ENDIF_ENTRY@@
  # ---- full-chain probes: client → node → internet, like a real user
  - job_name: chain
    scrape_interval: 30s
    scrape_timeout: 20s
    metrics_path: /probe
    static_configs:
@@IF_ENTRY@@
      - targets: ["https://www.gstatic.com/generate_204"]
        labels: { module: via_entry_vless, path: "RU-вход VLESS → США → интернет", node: entry, proto: vless }
      - targets: ["https://www.gstatic.com/generate_204"]
        labels: { module: via_entry_hy2, path: "RU-вход Hysteria2 → США → интернет", node: entry, proto: hy2 }
      - targets: ["https://ya.ru/"]
        labels: { module: via_entry_vless_ru, path: "RU-вход VLESS → RU-сайты напрямую", node: entry, proto: vless }
@@ENDIF_ENTRY@@
      - targets: ["https://www.gstatic.com/generate_204"]
        labels: { module: via_exit_vless, path: "США VLESS → интернет", node: exit, proto: vless }
      - targets: ["https://www.gstatic.com/generate_204"]
        labels: { module: via_exit_hy2, path: "США Hysteria2 → интернет", node: exit, proto: hy2 }
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [module]
        target_label: __param_module
      - source_labels: [__param_target]
        target_label: target
      - target_label: __address__
        replacement: 127.0.0.1:9115

  # ---- raw reachability + certificate expiry
  - job_name: reach
    metrics_path: /probe
    static_configs:
@@IF_ENTRY@@
      - targets: ["@@ENTRY_IP@@:443"]
        labels: { module: tcp, path: "RU TCP 443", node: entry }
@@ENDIF_ENTRY@@
      - targets: ["@@EXIT_IP@@:443"]
        labels: { module: tcp, path: "US TCP 443", node: exit }
      - targets: ["https://@@SUB_HOST@@:@@SUB_PORT@@/healthz"]
        labels: { module: https, path: "Подписки HTTPS", node: exit }
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [module]
        target_label: __param_module
      - source_labels: [__param_target]
        target_label: target
      - target_label: __address__
        replacement: 127.0.0.1:9115

  - job_name: blackbox
    static_configs:
      - targets: ["127.0.0.1:9115"]
        labels: { node: exit }
