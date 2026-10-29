FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc make libc6-dev python3 ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home --shell /bin/bash agent
RUN mkdir -p /app/regex
COPY workspace/ /app/regex/
RUN chown -R agent:agent /app
WORKDIR /app/regex
