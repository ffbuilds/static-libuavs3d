# syntax=docker/dockerfile:1

# bump: uavs3d /UAVS3D_COMMIT=([[:xdigit:]]+)/ gitrefs:https://github.com/uavs3/uavs3d.git|re:#^refs/heads/master$#|@commit
# bump: uavs3d after ./hashupdate Dockerfile UAVS3D $LATEST
# bump: uavs3d link "Source diff $CURRENT..$LATEST" https://github.com/uavs3/uavs3d/compare/$CURRENT..$LATEST
ARG UAVS3D_URL="https://github.com/uavs3/uavs3d.git"
ARG UAVS3D_COMMIT=0133ee4b4bbbef7b88802e7ad019b14b9b852c2b

# Must be specified
ARG ALPINE_VERSION

FROM alpine:${ALPINE_VERSION} AS base

FROM base AS download
ARG UAVS3D_URL
ARG UAVS3D_COMMIT
ARG WGET_OPTS="--retry-on-host-error --retry-on-http-error=429,500,502,503 -nv"
WORKDIR /tmp
RUN \
  apk add --no-cache --virtual download \
    git && \
  git clone "$UAVS3D_URL" && \
  cd uavs3d && git checkout $UAVS3D_COMMIT && \
  apk del download

FROM base AS build 
COPY --from=download /tmp/uavs3d/ /tmp/uavs3d/
ARG TARGETPLATFORM
WORKDIR /tmp/uavs3d/build/linux
RUN \
  case ${TARGETPLATFORM} in \
    linux/arm/v*) \
      # Fake it 'til we make it
      mkdir -p /usr/local/lib/pkgconfig/ && \
      touch /usr/local/lib/pkgconfig/uavs3d.pc && \
      touch /usr/local/lib/libuavs3d.a && \
      mkdir -p /usr/local/include/ && \
      touch /usr/local/include/uavs3d.h && \
      exit 0 \
    ;; \
  esac && \
  apk add --no-cache --virtual build \
    build-base cmake pkgconf && \
  # Removes BIT_DEPTH 10 to be able to build on other platforms. 10 was overkill anyways.
  #  sed -i 's/define BIT_DEPTH 8/define BIT_DEPTH 10/' source/decore/com_def.h && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    ../.. && \
  make -j$(nproc) install && \
  # Sanity tests
  pkg-config --exists --modversion --path uavs3d && \
  ar -t /usr/local/lib/libuavs3d.a && \
  readelf -h /usr/local/lib/libuavs3d.a && \
  # Cleanup
  apk del build

FROM scratch
ARG UAVS3D_COMMIT
COPY --from=build /usr/local/lib/pkgconfig/uavs3d.pc /usr/local/lib/pkgconfig/uavs3d.pc
COPY --from=build /usr/local/lib/libuavs3d.a /usr/local/lib/libuavs3d.a
COPY --from=build /usr/local/include/uavs3d.h /usr/local/include/uavs3d.h
