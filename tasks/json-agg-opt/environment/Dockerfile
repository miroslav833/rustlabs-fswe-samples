FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc make libc6-dev python3 ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home --shell /bin/bash agent
RUN mkdir -p /app/agg
COPY workspace/ /app/agg/
# Pre-build the baseline so `nop` leaves a correct-but-slow program in place;
# the grader rebuilds from source anyway.
RUN cd /app/agg && make >/dev/null 2>&1 || true
RUN chown -R agent:agent /app
WORKDIR /app/agg
