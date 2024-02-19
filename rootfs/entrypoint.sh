#!/bin/sh

set -e

if [[ -z "$SURFSHARK_OVPN_USERNAME" ]]; then
	echo "Error: \$SURFSHARK_OVPN_USERNAME is not set." >&2
	exit 2
fi
if [[ -z "$SURFSHARK_OVPN_PASSWORD" ]]; then
	echo "Error: \$SURFSHARK_OVPN_PASSWORD is not set." >&2
	exit 2
fi
if [[ -n "$SURFSHARK_OVPN_PROTOCOL" ]]; then
	if [[ "$SURFSHARK_OVPN_PROTOCOL" != "tcp" && "$SURFSHARK_OVPN_PROTOCOL" != "udp" ]]; then
		echo "Error: \$SURFSHARK_OVPN_PROTOCOL must be empty, tcp or udp." >&2
		exit 2
	fi
fi
if [[ -z "$SURFSHARK_OVPN_REMOTE_HOST" && -z "$SURFSHARK_OVPN_REMOTE_IP" ]]; then
	echo "Error: \$SURFSHARK_OVPN_REMOTE_HOST or \$SURFSHARK_OVPN_REMOTE_IP must be set." >&2
	exit 2
fi
if [[ -n "$SURFSHARK_OVPN_REMOTE_HOST" && -n "$SURFSHARK_OVPN_REMOTE_IP" ]]; then
	echo "Error: \$SURFSHARK_OVPN_REMOTE_HOST and \$SURFSHARK_OVPN_REMOTE_IP cannot be set at the same time." >&2
	exit 2
fi

export TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

[[ $(sysctl -n net.ipv6.conf.all.disable_ipv6) -eq 0 ]] && sysctl -w net.ipv6.conf.all.disable_ipv6=1
[[ $(sysctl -n net.ipv6.conf.default.disable_ipv6) -eq 0 ]] && sysctl -w net.ipv6.conf.default.disable_ipv6=1
[[ $(sysctl -n net.ipv6.conf.lo.disable_ipv6) -eq 0 ]] && sysctl -w net.ipv6.conf.lo.disable_ipv6=1

DEFAULT_ROUTE_VIA=$(ip route show default 0.0.0.0/0 | head -1 | cut -d ' ' -f 3-)

SURFSHARK_OVPN_PROTOCOL=${SURFSHARK_OVPN_PROTOCOL:-udp}

if [[ -n "$SURFSHARK_OVPN_REMOTE_HOST" ]]; then
	SURFSHARK_OVPN_REMOTE_IP=$(dig +short $SURFSHARK_OVPN_REMOTE_HOST A | grep -v "\.$" | head -1)
	if [[ -z "$SURFSHARK_OVPN_REMOTE_IP" ]]; then
		echo "Error: No DNS A records found for $SURFSHARK_OVPN_REMOTE_HOST." >&2
		exit 1
	fi
fi
echo "$SURFSHARK_OVPN_REMOTE_IP" > /tmp/surfshark-ovpn-remote-ip
[[ $(ip route show $SURFSHARK_OVPN_REMOTE_IP | wc -l) -eq 0 ]] && ip route add $SURFSHARK_OVPN_REMOTE_IP via $DEFAULT_ROUTE_VIA

SURFSHARK_OVPN_REMOTE_PORT=${SURFSHARK_OVPN_REMOTE_PORT:-$([[ "$SURFSHARK_OVPN_PROTOCOL" == "udp" ]] && echo "1194" || echo "1443")}

SURFSHARK_OVPN_AUTH_USER_PASS_FILE=$(mktemp)
chmod 600 $SURFSHARK_OVPN_AUTH_USER_PASS_FILE
cat << EOF > $SURFSHARK_OVPN_AUTH_USER_PASS_FILE
$SURFSHARK_OVPN_USERNAME
$SURFSHARK_OVPN_PASSWORD
EOF

SURFSHARK_OVPN_CONF_FILE=$(mktemp)
chmod 600 $SURFSHARK_OVPN_CONF_FILE
cat << EOF > $SURFSHARK_OVPN_CONF_FILE
client
proto $SURFSHARK_OVPN_PROTOCOL
remote $SURFSHARK_OVPN_REMOTE_IP $SURFSHARK_OVPN_REMOTE_PORT
remote-cert-tls server
dev surfshark-ovpn
dev-type tun
tun-mtu 1280
nobind
fast-io
mute-replay-warnings
ping 15
ping-restart 30

pull-filter ignore "dhcp-option DNS"
pull-filter ignore block-outside-dns
pull-filter ignore redirect-gateway
pull-filter ignore "route "

route 0.0.0.0 192.0.0.0
route 64.0.0.0 224.0.0.0
route 96.0.0.0 240.0.0.0
route 112.0.0.0 248.0.0.0
route 120.0.0.0 252.0.0.0
route 124.0.0.0 254.0.0.0
route 126.0.0.0 255.0.0.0
route 128.0.0.0 128.0.0.0

auth SHA512
auth-user-pass $SURFSHARK_OVPN_AUTH_USER_PASS_FILE
auth-nocache
cipher AES-256-CBC
<ca>
-----BEGIN CERTIFICATE-----
MIIFTTCCAzWgAwIBAgIJAMs9S3fqwv+mMA0GCSqGSIb3DQEBCwUAMD0xCzAJBgNV
BAYTAlZHMRIwEAYDVQQKDAlTdXJmc2hhcmsxGjAYBgNVBAMMEVN1cmZzaGFyayBS
b290IENBMB4XDTE4MDMxNDA4NTkyM1oXDTI4MDMxMTA4NTkyM1owPTELMAkGA1UE
BhMCVkcxEjAQBgNVBAoMCVN1cmZzaGFyazEaMBgGA1UEAwwRU3VyZnNoYXJrIFJv
b3QgQ0EwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDEGMNj0aisM63o
SkmVJyZPaYX7aPsZtzsxo6m6p5Wta3MGASoryRsBuRaH6VVa0fwbI1nw5ubyxkua
Na4v3zHVwuSq6F1p8S811+1YP1av+jqDcMyojH0ujZSHIcb/i5LtaHNXBQ3qN48C
c7sqBnTIIFpmb5HthQ/4pW+a82b1guM5dZHsh7q+LKQDIGmvtMtO1+NEnmj81BAp
FayiaD1ggvwDI4x7o/Y3ksfWSCHnqXGyqzSFLh8QuQrTmWUm84YHGFxoI1/8AKdI
yVoB6BjcaMKtKs/pbctk6vkzmYf0XmGovDKPQF6MwUekchLjB5gSBNnptSQ9kNgn
TLqi0OpSwI6ixX52Ksva6UM8P01ZIhWZ6ua/T/tArgODy5JZMW+pQ1A6L0b7egIe
ghpwKnPRG+5CzgO0J5UE6gv000mqbmC3CbiS8xi2xuNgruAyY2hUOoV9/BuBev8t
tE5ZCsJH3YlG6NtbZ9hPc61GiBSx8NJnX5QHyCnfic/X87eST/amZsZCAOJ5v4EP
SaKrItt+HrEFWZQIq4fJmHJNNbYvWzCE08AL+5/6Z+lxb/Bm3dapx2zdit3x2e+m
iGHekuiE8lQWD0rXD4+T+nDRi3X+kyt8Ex/8qRiUfrisrSHFzVMRungIMGdO9O/z
CINFrb7wahm4PqU2f12Z9TRCOTXciQIDAQABo1AwTjAdBgNVHQ4EFgQUYRpbQwyD
ahLMN3F2ony3+UqOYOgwHwYDVR0jBBgwFoAUYRpbQwyDahLMN3F2ony3+UqOYOgw
DAYDVR0TBAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAgEAn9zV7F/XVnFNZhHFrt0Z
S1Yqz+qM9CojLmiyblMFh0p7t+Hh+VKVgMwrz0LwDH4UsOosXA28eJPmech6/bjf
ymkoXISy/NUSTFpUChGO9RabGGxJsT4dugOw9MPaIVZffny4qYOc/rXDXDSfF2b+
303lLPI43y9qoe0oyZ1vtk/UKG75FkWfFUogGNbpOkuz+et5Y0aIEiyg0yh6/l5Q
5h8+yom0HZnREHhqieGbkaGKLkyu7zQ4D4tRK/mBhd8nv+09GtPEG+D5LPbabFVx
KjBMP4Vp24WuSUOqcGSsURHevawPVBfgmsxf1UCjelaIwngdh6WfNCRXa5QQPQTK
ubQvkvXONCDdhmdXQccnRX1nJWhPYi0onffvjsWUfztRypsKzX4dvM9k7xnIcGSG
EnCC4RCgt1UiZIj7frcCMssbA6vJ9naM0s7JF7N3VKeHJtqe1OCRHMYnWUZt9vrq
X6IoIHlZCoLlv39wFW9QNxelcAOCVbD+19MZ0ZXt7LitjIqe7yF5WxDQN4xru087
FzQ4Hfj7eH1SNLLyKZkA1eecjmRoi/OoqAt7afSnwtQLtMUc2bQDg6rHt5C0e4dC
LqP/9PGZTSJiwmtRHJ/N5qYWIh9ju83APvLm/AGBTR2pXmj9G3KdVOkpIC7L35dI
623cSEC3Q3UZutsEm/UplsM=
-----END CERTIFICATE-----
</ca>
key-direction 1
<tls-auth>
#
# 2048 bit OpenVPN static key
#
-----BEGIN OpenVPN Static key V1-----
b02cb1d7c6fee5d4f89b8de72b51a8d0
c7b282631d6fc19be1df6ebae9e2779e
6d9f097058a31c97f57f0c35526a44ae
09a01d1284b50b954d9246725a1ead1f
f224a102ed9ab3da0152a15525643b2e
ee226c37041dc55539d475183b889a10
e18bb94f079a4a49888da566b9978346
0ece01daaf93548beea6c827d9674897
e7279ff1a19cb092659e8c1860fbad0d
b4ad0ad5732f1af4655dbd66214e552f
04ed8fd0104e1d4bf99c249ac229ce16
9d9ba22068c6c0ab742424760911d463
6aafb4b85f0c952a9ce4275bc821391a
a65fcd0d2394f006e3fba0fd34c4bc4a
b260f4b45dec3285875589c97d3087c9
134d3a3aa2f904512e85aa2dc2202498
-----END OpenVPN Static key V1-----
</tls-auth>
EOF

SURFSHARK_OVPN_NAT_RULE="POSTROUTING -o surfshark-ovpn -j MASQUERADE"
if ! iptables -t nat -C $SURFSHARK_OVPN_NAT_RULE &> /dev/null; then
	iptables -t nat -A $SURFSHARK_OVPN_NAT_RULE
fi

SURFSHARK_OVPN_EXCLUDED_ROUTES=10.0.0.0/8,100.64.0.0/10,169.254.0.0/16,172.16.0.0/12,192.0.0.0/24,192.168.0.0/16,224.0.0.0/24,240.0.0.0/4,239.255.255.250/32,255.255.255.255/32
for ROUTE in $(echo "$SURFSHARK_OVPN_EXCLUDED_ROUTES,$SURFSHARK_OVPN_EXTRA_EXCLUDED_ROUTES" | tr , "\n"); do
	[[ $(ip route show $ROUTE | wc -l) -eq 0 ]] && ip route add $ROUTE via $DEFAULT_ROUTE_VIA
done

if [[ $# -gt 0 ]]; then
	openvpn --daemon surfshark-ovpn --config $SURFSHARK_OVPN_CONF_FILE
	surfshark-liveness-probe
	exec "$@"
else
	exec openvpn --config $SURFSHARK_OVPN_CONF_FILE
fi
