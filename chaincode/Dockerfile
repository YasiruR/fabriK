# syntax=docker/dockerfile:1
FROM golang:1.19-alpine

WORKDIR /go/github.com/YasiruR/fabriK/chaincode

COPY go.mod go.sum ./
COPY start.go ./
RUN go mod download
COPY asset ./asset/

RUN CGO_ENABLED=0 GOOS=linux go build -o asset-cc-8-0
EXPOSE 6051

CMD ["/go/github.com/YasiruR/fabriK/chaincode/asset-cc-8-0"]
