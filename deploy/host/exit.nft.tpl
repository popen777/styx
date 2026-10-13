# Styx 2 — US/exit firewall (rendered by styxctl, applied on deploy)
# Docker's own tables are untouched: everything runs with host networking.
table inet styx
delete table inet styx

table inet styx {
    chain input {
        type filter hook input priority filter - 5; policy drop;

        ct state established,related accept
        ct state invalid drop
        iif lo accept
        iifname "docker0" accept
        iifname "br-*" accept

        ip protocol icmp icmp type { echo-request, destination-unreachable, time-exceeded } limit rate 20/second accept
        ip6 nexthdr icmpv6 accept

        tcp dport @@EXIT_SSH_PORT@@ ct state new limit rate 30/minute accept comment "ssh"
        tcp dport 80 accept comment "acme http-01"
        tcp dport 443 accept comment "vless reality"
        udp dport 443 accept comment "hysteria2"
        udp dport @@HOP_START@@-@@HOP_END@@ accept comment "hysteria2 port hopping"
        tcp dport @@SUB_PORT@@ accept comment "subscriptions + grafana"
@@IF_ENTRY@@
        ip saddr @@ENTRY_IP@@ tcp dport @@BRIDGE_PORT@@ accept comment "RU->US xhttp tunnel"
@@ENDIF_ENTRY@@
@@IF_AWG@@
        udp dport @@AWG_PORT@@ accept comment "amneziawg"
@@ENDIF_AWG@@
    }

    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        udp dport @@HOP_START@@-@@HOP_END@@ redirect to :443 comment "hysteria2 port hopping"
    }
}
