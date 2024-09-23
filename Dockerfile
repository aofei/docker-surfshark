FROM alpine:3.20
COPY rootfs/ /
RUN apk add --no-cache iptables openvpn
ENTRYPOINT ["/entrypoint.sh"]
