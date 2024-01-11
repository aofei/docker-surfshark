FROM alpine:3.19
COPY rootfs/ /
RUN apk add --no-cache openvpn iproute2 iptables ip6tables bind-tools
ENTRYPOINT ["/entrypoint.sh"]
