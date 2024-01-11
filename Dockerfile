FROM alpine:3.19
COPY rootfs/ /
RUN apk add --no-cache wireguard-tools iproute2 iptables ip6tables curl jq bind-tools
ENTRYPOINT ["/entrypoint.sh"]
