#!/bin/sh

set -e

if [[ -z "${SURFSHARK_WG_PRIVATE_KEY}" ]]; then
	echo "Error: SURFSHARK_WG_PRIVATE_KEY is not set." >&2
	exit 2
fi
if [[ -z "${SURFSHARK_WG_PEER_LOCATION}" ]]; then
	echo "Error: SURFSHARK_WG_PEER_LOCATION is not set." >&2
	exit 2
fi

SURFSHARK_WG_PEER_SERVER="$(wget -qO- https://api.surfshark.com/v3/server/clusters | \
	jq --arg location "${SURFSHARK_WG_PEER_LOCATION}" \
	-r 'first(.[] | select(.location == $location))')"
if [[ -z "${SURFSHARK_WG_PEER_SERVER}" ]]; then
	echo "Error: Failed to find a server for the Surfshark WireGuard peer location ${SURFSHARK_WG_PEER_LOCATION}." >&2
	exit 1
fi

SURFSHARK_WG_PEER_PUBLIC_KEY="$(echo "${SURFSHARK_WG_PEER_SERVER}" | jq -r '.pubKey')"
if [[ -z "${SURFSHARK_WG_PEER_PUBLIC_KEY}" ]]; then
	echo "Error: Failed to find a public key for the Surfshark WireGuard peer location ${SURFSHARK_WG_PEER_LOCATION}." >&2
	exit 1
fi

SURFSHARK_WG_PEER_ENDPOINT="${SURFSHARK_WG_PEER_ENDPOINT:-"$(echo "${SURFSHARK_WG_PEER_SERVER}" | jq -r '.connectionName'):51820"}"
if [[ -z "${SURFSHARK_WG_PEER_ENDPOINT}" ]]; then
	echo "Error: Failed to find an endpoint for the Surfshark WireGuard peer location ${SURFSHARK_WG_PEER_LOCATION}." >&2
	exit 1
fi

export TMPDIR="$(mktemp -d)"
trap "rm -rf \"${TMPDIR}\"" EXIT

DEFAULT_ROUTE_VIA="$(ip route show default 0.0.0.0/0 | head -1 | cut -d ' ' -f 3-)"

SURFSHARK_STATE_DIR=/var/lib/surfshark
mkdir -p "${SURFSHARK_STATE_DIR}"

ADD_ROUTES_SCRIPT="$(mktemp)"
chmod +x "${ADD_ROUTES_SCRIPT}"
cat << EOF > "${ADD_ROUTES_SCRIPT}"
#!/bin/sh
set -e
for ROUTE in \$(echo "\$1" | tr , "\n"); do
	[[ -z "\${ROUTE}" ]] && continue
	ip route show "\${ROUTE}" | grep -q . || ip route add "\${ROUTE}" \$2
done
EOF

"${ADD_ROUTES_SCRIPT}" "${SURFSHARK_EXCLUDED_ROUTES}${SURFSHARK_EXTRA_EXCLUDED_ROUTES:+",${SURFSHARK_EXTRA_EXCLUDED_ROUTES}"}" "via ${DEFAULT_ROUTE_VIA}"

SURFSHARK_WG_POSTUP_SCRIPT="$(mktemp)"
chmod +x "${SURFSHARK_WG_POSTUP_SCRIPT}"
cat << EOF > "${SURFSHARK_WG_POSTUP_SCRIPT}"
#!/bin/sh
set -e
SURFSHARK_WG_PEER_IP="\$(wg show surfshark0 endpoints | awk '{ print \$2 }' | cut -d: -f1)"
echo "\${SURFSHARK_WG_PEER_IP}" > "${SURFSHARK_STATE_DIR}/wg-peer-ip"
"${ADD_ROUTES_SCRIPT}" "\${SURFSHARK_WG_PEER_IP}" "via ${DEFAULT_ROUTE_VIA}"
EOF

SURFSHARK_WG_CONF_FILE="${TMPDIR}/surfshark0.conf"
touch "${SURFSHARK_WG_CONF_FILE}"
chmod 600 "${SURFSHARK_WG_CONF_FILE}"
cat << EOF > "${SURFSHARK_WG_CONF_FILE}"
[Interface]
PrivateKey = ${SURFSHARK_WG_PRIVATE_KEY}
Address = 10.14.0.2/16
ListenPort = 51820
MTU = 1280
PostUp = ${SURFSHARK_WG_POSTUP_SCRIPT}

[Peer]
PublicKey = ${SURFSHARK_WG_PEER_PUBLIC_KEY}
Endpoint = ${SURFSHARK_WG_PEER_ENDPOINT}
PersistentKeepalive = 25
AllowedIPs = ${SURFSHARK_INCLUDED_ROUTES}${SURFSHARK_EXTRA_INCLUDED_ROUTES:+",${SURFSHARK_EXTRA_INCLUDED_ROUTES}"}
EOF

wg show surfshark0 &> /dev/null || wg-quick up "${SURFSHARK_WG_CONF_FILE}"
if [[ $# -gt 0 ]]; then
	while [[ ! -d /sys/class/net/surfshark0 ]]; do sleep 0.1; done
	exec "$@"
else
	exec sh -c "trap : TERM INT; sleep infinity & wait"
fi
