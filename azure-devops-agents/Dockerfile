FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl \
    git \
    jq \
    libicu-dev \
    libssl-dev \
    libunwind8 \
    ca-certificates \
    unzip \
    zip \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash agent

WORKDIR /azp

COPY agent.tar.gz ./
RUN tar -xzf agent.tar.gz && rm agent.tar.gz

COPY start.sh ./
RUN chmod +x start.sh \
    && chown -R agent:agent /azp

RUN mkdir -p /workspace && chown agent:agent /workspace

USER agent

ENTRYPOINT ["./start.sh"]
