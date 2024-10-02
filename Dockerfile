FROM node:16.14.0-alpine AS frontend
LABEL maintainer="Statping-ng (https://github.com/statping-ng)"
ARG BUILDPLATFORM
WORKDIR /statping
COPY ./frontend/package.json .
COPY ./frontend/yarn.lock .
RUN yarn install --pure-lockfile --network-timeout 1000000
COPY ./frontend .
RUN yarn build && yarn cache clean

# Statping Golang BACKEND building from source
# Creates "/go/bin/statping" and "/usr/local/bin/sass" for copying
FROM golang:1.20.0-alpine AS backend
#FROM ubuntu:24.04 AS backend
LABEL maintainer="Statping-NG (https://github.com/statping-ng)"
ARG VERSION
ARG COMMIT
ARG BUILDPLATFORM
ARG TARGETARCH
RUN apk add --no-cache libstdc++ gcc g++ make git autoconf \
    libtool ca-certificates linux-headers wget curl jq && \
    update-ca-certificates

# Install necessary dependencies and Go 1.20
# RUN apt-get update && apt-get install -y \
#     libstdc++6 gcc g++ make git autoconf \
#     libtool ca-certificates linux-headers-generic wget curl jq \
#     && wget https://golang.org/dl/go1.20.11.linux-amd64.tar.gz \
#     && tar -C /usr/local -xzf go1.20.11.linux-amd64.tar.gz \
#     && rm go1.20.11.linux-amd64.tar.gz \
#     && ln -s /usr/local/go/bin/go /usr/bin/go \
#     && update-ca-certificates
# Set environment variables for Go
#ENV PATH="/usr/local/go/bin:${PATH}"

WORKDIR /root
RUN git clone --depth 1 --branch 3.6.2 https://github.com/sass/sassc.git
RUN . sassc/script/bootstrap && make -C sassc -j4
# sassc binary: /root/sassc/bin/sassc

WORKDIR /go/src/github.com/statping-ng/statping-ng
ADD go.mod go.sum ./
RUN go mod download
ENV GO111MODULE on
ENV CGO_ENABLED 1
COPY cmd ./cmd
COPY database ./database
COPY handlers ./handlers
COPY notifiers ./notifiers
COPY source ./source
COPY types ./types
COPY utils ./utils
COPY --from=frontend /statping/dist/ ./source/dist/
RUN go install github.com/GeertJohan/go.rice/rice@latest
#RUN cd source && $HOME/go/bin/rice embed-go
RUN cd source && rice embed-go
RUN go build -a -ldflags "-s -w -extldflags -static -X main.VERSION=$VERSION -X main.COMMIT=$COMMIT" -o statping --tags "netgo linux" ./cmd
#RUN chmod a+x statping && mv statping $HOME/go/bin/statping
RUN chmod a+x statping && mv statping /go/bin/statping
# /go/bin/statping - statping binary
# /root/sassc/bin/sassc - sass binary
# /statping - Vue frontend (from frontend)

# Statping main Docker image that contains all required libraries
FROM alpine:latest
#FROM ubuntu:24.04

RUN apk --no-cache add libgcc libstdc++ ca-certificates curl jq && update-ca-certificates
#RUN apt-get update && apt-get install -y \
#    libgcc-s1 libstdc++6 ca-certificates curl jq && \
#    update-ca-certificates && \
#    rm -rf /var/lib/apt/lists/*


#COPY --from=backend /root/go/bin/statping /usr/local/bin/
COPY --from=backend go/bin/statping /usr/local/bin/
COPY --from=backend /root/sassc/bin/sassc /usr/local/bin/
COPY --from=backend /usr/local/share/ca-certificates /usr/local/share/

WORKDIR /app
VOLUME /app

ENV IS_DOCKER=true
ENV SASS=/usr/local/bin/sassc
ENV STATPING_DIR=/app
ENV PORT=8080
ENV BASE_PATH=""

EXPOSE $PORT

HEALTHCHECK --interval=60s --timeout=10s --retries=3 CMD if [ -z "$BASE_PATH" ]; then HEALTHPATH="/health"; else HEALTHPATH="/$BASE_PATH/health" ; fi && curl -s "http://localhost:${PORT}$HEALTHPATH" | jq -r -e ".online==true"

CMD statping --port $PORT
