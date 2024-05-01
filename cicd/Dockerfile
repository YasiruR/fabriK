# syntax=docker/dockerfile:1
FROM golang:1.19-alpine

WORKDIR /go/github.com/YasiruR/fabriK/chaincode

COPY /home/yasi/go/src/github.com/YasiruR/fabriK/chaincode/go.mod /home/yasi/go/src/github.com/YasiruR/fabriK/chaincode/go.sum ./
COPY /home/yasi/go/src/github.com/YasiruR/fabriK/chaincode/start.go ./
RUN go mod download
COPY /home/yasi/go/src/github.com/YasiruR/fabriK/chaincode/asset ./asset/

RUN CGO_ENABLED=0 GOOS=linux go build -o asset-cc-0-7
EXPOSE 5005

CMD ["/go/github.com/YasiruR/fabriK/chaincode/asset-cc-0-7"]
