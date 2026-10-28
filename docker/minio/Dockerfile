# MinIO Community no longer publishes maintained container images.
# Like the official Vernissage installer, we therefore build the last
# security-fixed release from source.
ARG MINIO_RELEASE=RELEASE.2025-10-15T17-29-55Z

FROM golang:1.24.8-alpine AS build
ARG MINIO_RELEASE
RUN apk add --no-cache ca-certificates git
RUN CGO_ENABLED=0 GOBIN=/out go install github.com/minio/minio@${MINIO_RELEASE}

FROM alpine:3.22
RUN apk add --no-cache ca-certificates curl
COPY --from=build /out/minio /usr/local/bin/minio
VOLUME ["/data"]
EXPOSE 9000 9001
ENTRYPOINT ["minio"]
CMD ["server", "/data", "--console-address", ":9001"]
