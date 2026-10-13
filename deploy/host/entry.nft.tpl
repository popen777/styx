# Styx 2 — RU/entry firewall (rendered by styxctl on the exit node, applied over SSH)
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

        tcp dport @@ENTRY_SSH_PORT@@ ct state new limit rate 30/minute accept comment "ssh"
        tcp dport 443 accept comment "vless reality"
        udp dport 443 accept comment "hysteria2"
        udp dport @@HOP_START@@-@@HOP_END@@ accept comment "hysteria2 port hopping"
        @@MTPROTO_RULE@@
    }

    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        udp dport @@HOP_START@@-@@HOP_END@@ redirect to :443 comment "hysteria2 port hopping"
    }
}
