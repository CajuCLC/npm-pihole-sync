FROM alpine:latest
RUN apk add --no-cache curl
COPY sync.sh /sync.sh
RUN chmod +x /sync.sh
ENTRYPOINT ["/sync.sh"]
