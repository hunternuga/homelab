FROM docker.io/library/golang:1.25-alpine AS builder
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
# CGO_ENABLED=0: modernc.org/sqlite is a pure-Go driver, so a static binary
# needs no C toolchain and no libc at runtime — that's what lets the final
# stage be distroless.
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /kcal ./cmd/kcal

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /kcal /kcal

VOLUME /data
EXPOSE 8080
ENTRYPOINT ["/kcal"]
