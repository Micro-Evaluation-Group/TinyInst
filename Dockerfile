FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    python3 \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tinyinst

COPY . .

RUN rm -rf build && mkdir build && cd build \
    && cmake -DCMAKE_BUILD_TYPE=Release .. \
    && cmake --build . --config Release -j$(nproc)

# Build the test target
RUN gcc -O0 -g -o build/test_target test_target.c

# Verify binaries exist
RUN ls -la build/litecov build/sslhook build/test_target
