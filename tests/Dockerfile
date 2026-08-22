# The CI Qt lane's packages, so a run here fails exactly where CI would,
# plus OpenCV for the syntax check the unit tests deliberately do without.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      qtbase5-dev \
      qtdeclarative5-dev \
      libqt5sql5-sqlite \
      libssl-dev \
      libopencv-dev \
      cmake \
      ninja-build \
      g++ \
      pkg-config \
 && rm -rf /var/lib/apt/lists/*
