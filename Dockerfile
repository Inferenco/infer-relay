FROM docker.io/library/rust:1-bookworm as builder
ARG CARGO_LOG
RUN apt-get update \
    && apt-get install -y cmake protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*
RUN USER=root cargo install cargo-auditable
RUN USER=root cargo new --bin infer-relay
WORKDIR ./infer-relay
COPY ./Cargo.toml ./Cargo.toml
COPY ./Cargo.lock ./Cargo.lock
# build dependencies only (caching)
RUN cargo auditable build --release --locked
# get rid of starter project code
RUN rm src/*.rs

# copy project source code
COPY ./src ./src
COPY ./proto ./proto
COPY ./build.rs ./build.rs

# build auditable release using locked deps
RUN rm ./target/release/deps/infer*relay*
RUN cargo auditable build --release --locked

FROM docker.io/library/debian:bookworm-slim

ARG APP=/usr/src/app
ARG APP_DATA=/usr/src/app/db
RUN apt-get update \
    && apt-get install -y ca-certificates tzdata sqlite3 libc6 curl \
    && rm -rf /var/lib/apt/lists/*

EXPOSE 8080

ENV TZ=Etc/UTC \
    APP_USER=appuser

RUN groupadd $APP_USER \
    && useradd -g $APP_USER $APP_USER \
    && mkdir -p ${APP} \
    && mkdir -p ${APP_DATA}

COPY --from=builder /infer-relay/target/release/infer-relay ${APP}/infer-relay

RUN chown -R $APP_USER:$APP_USER ${APP}

USER $APP_USER
WORKDIR ${APP}

ENV RUST_LOG=info,infer_relay=info
ENV APP_DATA=${APP_DATA}

CMD ./infer-relay --db ${APP_DATA}
