# syntax=docker/dockerfile:1
FROM golang:1.19-alpine

RUN addgroup -S nonroot && adduser -S nonroot -G nonroot
USER nonroot

ARG CC_PORT
WORKDIR /go/chaincode

COPY go.mod go.sum ./
COPY start.go ./
RUN go mod download
COPY asset ./asset/

RUN CGO_ENABLED=0 GOOS=linux go build -o asset-cc
EXPOSE $CC_PORT

CMD ["/go/chaincode/asset-cc"]
