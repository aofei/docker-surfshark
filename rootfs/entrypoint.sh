#!/bin/sh

set -e

if [[ -z "$WG_SURFSHARK_IFACE_PRIVATE_KEY" ]]; then
	echo "Error: \$WG_SURFSHARK_IFACE_PRIVATE_KEY is not set." >&2
	exit 2
fi
if [[ -z "$WG_SURFSHARK_PEER_ENDPOINT_DOMAIN" ]]; then
	echo "Error: \$WG_SURFSHARK_PEER_ENDPOINT_DOMAIN is not set." >&2
	exit 2
fi

export TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

[[ $(sysctl -n net.ipv6.conf.all.disable_ipv6) -eq 0 ]] && sysctl -w net.ipv6.conf.all.disable_ipv6=1
[[ $(sysctl -n net.ipv6.conf.default.disable_ipv6) -eq 0 ]] && sysctl -w net.ipv6.conf.default.disable_ipv6=1
[[ $(sysctl -n net.ipv6.conf.lo.disable_ipv6) -eq 0 ]] && sysctl -w net.ipv6.conf.lo.disable_ipv6=1

DEFAULT_ROUTE_VIA=$(ip route show default | cut -d ' ' -f 3-)
WG_SURFSHARK_PEER_PUBLIC_KEY=$(curl -fsSL https://api.surfshark.com/v3/server/clusters | jq -r --arg domain "$WG_SURFSHARK_PEER_ENDPOINT_DOMAIN" '.[] | select( .connectionName == $domain ) | .pubKey')
WG_SURFSHARK_PEER_ENDPOINT_IP=$(dig +short $WG_SURFSHARK_PEER_ENDPOINT_DOMAIN A | head -1)
if [[ -z "$WG_SURFSHARK_PEER_ENDPOINT_IP" ]]; then
	echo "Error: No DNS A records found for $WG_SURFSHARK_PEER_ENDPOINT_DOMAIN." >&2
	exit 1
fi

WG_SURFSHARK_CONF_FILE=/etc/wireguard/wg-surfshark.conf
NEW_WG_SURFSHARK_CONF_FILE=$(mktemp)
chmod 600 $NEW_WG_SURFSHARK_CONF_FILE
cat << EOF > $NEW_WG_SURFSHARK_CONF_FILE
[Interface]
PrivateKey = $WG_SURFSHARK_IFACE_PRIVATE_KEY
Address = 10.14.0.2/16
MTU = 1380
PreUp = sh -c "ip route add $WG_SURFSHARK_PEER_ENDPOINT_IP via $DEFAULT_ROUTE_VIA"
PostDown = sh -c "ip route del \$(ip route show $WG_SURFSHARK_PEER_ENDPOINT_IP)"
PostUp = iptables -t nat -A POSTROUTING -o %i -j MASQUERADE
PreDown = iptables -t nat -D POSTROUTING -o %i -j MASQUERADE
[Peer]
PublicKey = $WG_SURFSHARK_PEER_PUBLIC_KEY
Endpoint = $WG_SURFSHARK_PEER_ENDPOINT_IP:51820
PersistentKeepalive = 25
AllowedIPs = 0.0.0.0/2, 64.0.0.0/3, 96.0.0.0/4, 112.0.0.0/5, 120.0.0.0/6, 124.0.0.0/7, 126.0.0.0/8, 128.0.0.0/1
EOF
if [[ ! -f $WG_SURFSHARK_CONF_FILE ]]; then
	mv $NEW_WG_SURFSHARK_CONF_FILE $WG_SURFSHARK_CONF_FILE
elif ! diff -q $WG_SURFSHARK_CONF_FILE $NEW_WG_SURFSHARK_CONF_FILE &> /dev/null; then
	WG_SURFSHARK_CONF_FILE_CHANGED=1
	mv $NEW_WG_SURFSHARK_CONF_FILE $WG_SURFSHARK_CONF_FILE
fi

WG_SURFSHARK_EXCLUDED_ROUTES=10.0.0.0/8,100.64.0.0/10,169.254.0.0/16,172.16.0.0/12,192.0.0.0/24,192.168.0.0/16,224.0.0.0/24,240.0.0.0/4,239.255.255.250/32,255.255.255.255/32
for ROUTE in $(echo "$WG_SURFSHARK_EXCLUDED_ROUTES,$WG_SURFSHARK_EXTRA_EXCLUDED_ROUTES" | tr , "\n"); do
	[[ $(ip route show $ROUTE | wc -l) -eq 0 ]] && ip route add $ROUTE via $DEFAULT_ROUTE_VIA
done

if ! wg show wg-surfshark &> /dev/null; then
	wg-quick up $WG_SURFSHARK_CONF_FILE
elif [[ "$WG_SURFSHARK_CONF_FILE_CHANGED" -eq 1 ]]; then
	wg-quick down $WG_SURFSHARK_CONF_FILE
	wg-quick up $WG_SURFSHARK_CONF_FILE
fi

surfshark-liveness-probe

if [[ $# -gt 0 ]]; then
	exec "$@"
else
	trap "exit 0" SIGHUP SIGINT SIGQUIT SIGABRT SIGALRM SIGTERM
	tail -f /dev/null &
	wait
fi
