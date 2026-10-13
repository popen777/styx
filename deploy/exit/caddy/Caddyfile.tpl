# Styx 2 — subscriptions + Grafana over HTTPS (port @@SUB_PORT@@).
# TCP 443 belongs to Xray Reality, so Caddy serves HTTPS on @@SUB_PORT@@ and
# solves ACME via HTTP-01 on port 80.
{
	email @@ACME_EMAIL@@
	acme_ca https://acme-v02.api.letsencrypt.org/directory
	http_port 80
	https_port @@SUB_PORT@@
	admin off
	servers {
		protocols h1 h2
	}
}

(sub_headers) {
	header {
		Content-Type "text/plain; charset=utf-8"
		Cache-Control "no-store"
		profile-title "base64:@@SERVER_NAME_B64@@"
		profile-update-interval "6"
		X-Robots-Tag "noindex, nofollow"
		-Server
	}
}

@@SUB_HOST@@:@@SUB_PORT@@ {
	encode gzip

	@happ {
		path_regexp tok ^/s/([A-Za-z0-9_-]{16,64})$
		header_regexp ua User-Agent (?i)happ
	}
	@v2raytun {
		path_regexp tok ^/s/([A-Za-z0-9_-]{16,64})$
		header_regexp ua User-Agent (?i)v2raytun
	}
	@sub path_regexp tok ^/s/([A-Za-z0-9_-]{16,64})$
	@awg path_regexp awg ^/s/([A-Za-z0-9_-]{16,64})/([a-z0-9_.-]{1,32})\.conf$

	# AmneziaWG config for a device (router / app): /s/<token>/<device>.conf
	handle @awg {
		header {
			Content-Type "text/plain; charset=utf-8"
			Content-Disposition "attachment; filename=\"@@AWG_FILE_PREFIX@@-{re.awg.2}.conf\""
			Cache-Control "no-store"
			-Server
		}
		root * /srv/sub
		rewrite * /{re.awg.1}.{re.awg.2}.conf
		file_server
	}

	handle @happ {
		import sub_headers
		root * /srv/sub
		rewrite * /{re.tok.1}.happ
		file_server
	}
	handle @v2raytun {
		import sub_headers
		header routing "@@V2RAYTUN_ROUTING_B64@@"
		root * /srv/sub
		rewrite * /{re.tok.1}.txt
		file_server
	}
	handle @sub {
		import sub_headers
		root * /srv/sub
		rewrite * /{re.tok.1}.txt
		file_server
	}

	handle /grafana* {
		reverse_proxy 127.0.0.1:3000
	}

	handle /healthz {
		respond "ok" 200
	}

	handle {
		header -Server
		respond 404
	}
}

# Only needed so Caddy obtains (and renews) the certificate that Hysteria2 uses
# on both nodes. Hysteria re-reads the files on every handshake.
@@HY_HOST@@:@@SUB_PORT@@ {
	header -Server
	respond 404
}
