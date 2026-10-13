# Styx 2 — Alertmanager (rendered by styxctl)
route:
  receiver: telegram
  group_by: [alertname, node, path, tag]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 3h
  routes:
    - matchers: [alertname = Watchdog]
      receiver: deadman
      group_wait: 0s
      group_interval: 1m
      repeat_interval: 1m
    - matchers: [severity = info]
      receiver: telegram
      repeat_interval: 24h

inhibit_rules:
  # whole RU entry down → don't spam per-chain alerts for it
  - source_matchers: [alertname = RuEntryFullyDown]
    target_matchers: [node = entry]
    equal: []
  - source_matchers: [alertname = RuUsAllLinksDown]
    target_matchers: [alertname = RuUsLinkDown]

receivers:
  - name: telegram
    telegram_configs:
      - bot_token: "@@TELEGRAM_BOT_TOKEN@@"
        chat_id: @@TELEGRAM_CHAT_ID@@
        parse_mode: HTML
        send_resolved: true
        message: |-
          {{ if eq .Status "firing" }}🔴{{ else }}🟢{{ end }} <b>@@SERVER_NAME@@</b>
          {{ range .Alerts }}{{ if eq .Status "firing" }}🔥{{ else }}✅{{ end }} {{ .Annotations.summary }}
          {{ with .Annotations.description }}<i>{{ . }}</i>
          {{ end }}{{ end }}
  - name: deadman
@@DEADMAN_BLOCK@@
