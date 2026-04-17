FROM node:24

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git curl python3 python3-pip build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Hardhat
RUN npm install -g hardhat

WORKDIR /workspaces/surepay
