# Archivematica Monolithic Dockerfile
# Based on Ubuntu 24.04 (Noble) using official deb packages
# Reference: https://www.archivematica.org/en/docs/archivematica-1.18/admin-manual/installation-setup/installation/install-ubuntu/

FROM ubuntu:24.04

LABEL maintainer="Archivematica"
LABEL description="Monolithic Archivematica installation using Ubuntu deb packages"
LABEL version="1.18.x"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Set default MySQL/database passwords for non-interactive installation
# These should be overridden at runtime for production use
ENV ARCHIVEMATICA_MCPSERVER_CLIENT_DATABASE="archivematica"
ENV ARCHIVEMATICA_MCPSERVER_CLIENT_USER="archivematica"
ENV ARCHIVEMATICA_MCPSERVER_CLIENT_PASSWORD="demo"
ENV SS_DB_NAME="SS_db"
ENV SS_DB_USER="ss"
ENV SS_DB_PASSWORD="demo"

# Step 1: Install prerequisites and add Archivematica repositories
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        gnupg \
        lsb-release \
        ca-certificates \
        apt-transport-https \
        software-properties-common && \
    # Create keyrings directory
    mkdir -p /etc/apt/keyrings && \
    # Add Archivematica GPG key
    curl -fsSL https://packages.archivematica.org/1.18.x/key.asc | gpg --dearmor -o /etc/apt/keyrings/archivematica-1.18.x.gpg && \
    # Add Archivematica main repository
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/archivematica-1.18.x.gpg] http://packages.archivematica.org/1.18.x/ubuntu noble main" > /etc/apt/sources.list.d/archivematica.list && \
    # Add Archivematica externals repository
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/archivematica-1.18.x.gpg] http://packages.archivematica.org/1.18.x/ubuntu-externals noble main" > /etc/apt/sources.list.d/archivematica-externals.list && \
    # Clean up
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Step 2: Add Elasticsearch package source
RUN curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /etc/apt/keyrings/elasticsearch-8.x.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/elasticsearch-8.x.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" > /etc/apt/sources.list.d/elastic-8.x.list

# Step 3: Update package lists
RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Step 4: Install needed packages (openjdk-8-jre-headless and mysql-server)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openjdk-8-jre-headless \
        mysql-server && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Step 5: Install Elasticsearch
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        elasticsearch && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Initialize MySQL data directory and start MySQL temporarily for package installations
# Pre-seed debconf answers for archivematica packages to avoid interactive prompts
RUN apt-get update && \
    apt-get install -y --no-install-recommends debconf-utils && \
    # Pre-seed Storage Service database configuration
    echo "archivematica-storage-service archivematica-storage-service/dbconfig-install boolean true" | debconf-set-selections && \
    echo "archivematica-storage-service archivematica-storage-service/mysql/admin-pass password " | debconf-set-selections && \
    echo "archivematica-storage-service archivematica-storage-service/mysql/app-pass password ${SS_DB_PASSWORD}" | debconf-set-selections && \
    echo "archivematica-storage-service archivematica-storage-service/app-password-confirm password ${SS_DB_PASSWORD}" | debconf-set-selections && \
    # Pre-seed MCP Server database configuration
    echo "archivematica-mcp-server archivematica-mcp-server/dbconfig-install boolean true" | debconf-set-selections && \
    echo "archivematica-mcp-server archivematica-mcp-server/mysql/admin-pass password " | debconf-set-selections && \
    echo "archivematica-mcp-server archivematica-mcp-server/mysql/app-pass password ${ARCHIVEMATICA_MCPSERVER_CLIENT_PASSWORD}" | debconf-set-selections && \
    echo "archivematica-mcp-server archivematica-mcp-server/app-password-confirm password ${ARCHIVEMATICA_MCPSERVER_CLIENT_PASSWORD}" | debconf-set-selections && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Step 6: Install the Storage Service
# MySQL must be running for the database configuration
RUN apt-get update && \
    # Initialize MySQL if needed and start it
    if [ ! -d /var/lib/mysql/mysql ]; then \
        mysqld --initialize-insecure --user=mysql; \
    fi && \
    service mysql start && \
    # Install Storage Service
    apt-get install -y archivematica-storage-service && \
    # Stop MySQL
    service mysql stop && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Step 7: Configure the Storage Service nginx
RUN rm -f /etc/nginx/sites-enabled/default && \
    ln -sf /etc/nginx/sites-available/storage /etc/nginx/sites-enabled/storage

# Step 8: Install the Archivematica packages
# Order is important: mcp-server must be installed before dashboard
RUN apt-get update && \
    # Start MySQL for database configuration
    service mysql start && \
    # Install archivematica-mcp-server first
    apt-get install -y archivematica-mcp-server && \
    # Install archivematica-dashboard
    apt-get install -y archivematica-dashboard && \
    # Install archivematica-mcp-client
    apt-get install -y archivematica-mcp-client && \
    # Stop MySQL
    service mysql stop && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Step 10: Configure the dashboard nginx
RUN ln -sf /etc/nginx/sites-available/dashboard.conf /etc/nginx/sites-enabled/dashboard.conf

# Step 11: Configure Elasticsearch (disable xpack security)
RUN sed -i -e 's/xpack.security.enabled: true/xpack.security.enabled: false/g' /etc/elasticsearch/elasticsearch.yml || true

# Expose ports
# 80 - Archivematica Dashboard (nginx)
# 8000 - Storage Service (nginx)
# 9200 - Elasticsearch
# 3306 - MySQL
EXPOSE 80 8000 9200 3306

# Set working directory
WORKDIR /

# Default command - Note: In production, you would use a process manager
# This is a simple entrypoint that starts all services
CMD service mysql start && \
    service elasticsearch start && \
    sleep 10 && \
    service clamav-freshclam restart && \
    sleep 30 && \
    service clamav-daemon start && \
    service gearman-job-server restart && \
    service archivematica-mcp-server start && \
    service archivematica-mcp-client start && \
    service archivematica-storage-service start && \
    service archivematica-dashboard start && \
    service nginx restart && \
    tail -f /var/log/archivematica/MCPServer/MCPServer.log