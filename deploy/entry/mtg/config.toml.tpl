# mtg v2 — MTProto proxy with FakeTLS. Outgoing connections to Telegram DCs go
# through local Xray (→ US), because Telegram DCs are throttled in RU.
secret = "@@MTPROTO_SECRET@@"
bind-to = "0.0.0.0:@@MTPROTO_PORT@@"
prefer-ip = "prefer-ipv4"

[network]
proxies = ["socks5://127.0.0.1:10808"]

[defense.anti-replay]
enabled = true
