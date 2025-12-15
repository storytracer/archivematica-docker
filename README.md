# Archivematica Monolithic Docker Image

A monolithic Docker image for [Archivematica](https://www.archivematica.org/) 1.18.x based on Ubuntu 24.04 (Noble), using the official deb packages.

> **Note:** This is a monolithic installation intended for development, testing, or small-scale deployments. For production environments, consider using a distributed setup with separate containers for each service.

## Prerequisites

- Docker 20.10 or later
- At least 4GB of RAM available for the container
- At least 10GB of disk space

## Quick Start

### 1. Build the Image

```bash
docker build -t archivematica:1.18 .
```

### 2. Configure Environment Variables

Copy the example environment file and modify the passwords:

```bash
cp .env.example .env
```

Edit `.env` and change all `CHANGE_ME_*` passwords to secure values.

### 3. Run the Container

```bash
docker run -d \
  --name archivematica \
  --env-file .env \
  -p 80:80 \
  -p 8000:8000 \
  archivematica:1.18
```

### 4. Wait for Services to Start

The container needs approximately 2-3 minutes for all services to initialize (especially ClamAV). Monitor the logs:

```bash
docker logs -f archivematica
```

Wait until you see log entries from MCPServer before proceeding.

### 5. Create Storage Service Admin User

Once the container is running, create an administrative user for the Storage Service:

```bash
docker exec -it archivematica bash -c " \
    set -a -e -x
    source /etc/default/archivematica-storage-service || \
        source /etc/sysconfig/archivematica-storage-service \
            || (echo 'Environment file not found'; exit 1)
    /usr/share/archivematica/virtualenvs/archivematica-storage-service/bin/python \
        -m archivematica.storage_service.manage createsuperuser
"
```

Follow the prompts to create your admin user. **Save the API key** that is generated—you'll need it later.

### 6. Access the Web Interfaces

- **Storage Service:** http://localhost:8000
- **Archivematica Dashboard:** http://localhost:80

### 7. Complete Post-Installation Setup

1. Log into the **Storage Service** at http://localhost:8000 with the admin user you created
2. Navigate to your user profile to find the **API key**
3. Access the **Archivematica Dashboard** at http://localhost:80
4. Complete the welcome wizard:
   - Enter organization name and identifier
   - Create a dashboard admin user
   - Connect to Storage Service using:
     - URL: `http://127.0.0.1:8000`
     - Username: (your Storage Service admin username)
     - API Key: (the key from step 2)

## Environment Variables

### Required Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SS_DB_NAME` | Storage Service database name | `SS_db` |
| `SS_DB_USER` | Storage Service database user | `ss` |
| `SS_DB_PASSWORD` | Storage Service database password | `demo` |
| `ARCHIVEMATICA_MCPSERVER_CLIENT_DATABASE` | MCP Server database name | `archivematica` |
| `ARCHIVEMATICA_MCPSERVER_CLIENT_USER` | MCP Server database user | `archivematica` |
| `ARCHIVEMATICA_MCPSERVER_CLIENT_PASSWORD` | MCP Server database password | `demo` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ARCHIVEMATICA_DASHBOARD_DASHBOARD_SEARCH_ENABLED` | Enable Elasticsearch for Dashboard | `true` |
| `ARCHIVEMATICA_MCPSERVER_MCPSERVER_SEARCH_ENABLED` | Enable Elasticsearch for MCP Server | `true` |
| `ARCHIVEMATICA_MCPCLIENT_MCPCLIENT_SEARCH_ENABLED` | Enable Elasticsearch for MCP Client | `true` |

## Exposed Ports

| Port | Service |
|------|---------|
| 80 | Archivematica Dashboard (nginx) |
| 8000 | Storage Service (nginx) |
| 9200 | Elasticsearch (internal) |
| 3306 | MySQL (internal) |

## Data Persistence

To persist data across container restarts, mount volumes for the following directories:

```bash
docker run -d \
  --name archivematica \
  --env-file .env \
  -p 80:80 \
  -p 8000:8000 \
  -v archivematica-mysql:/var/lib/mysql \
  -v archivematica-elasticsearch:/var/lib/elasticsearch \
  -v archivematica-data:/var/archivematica \
  archivematica:1.18
```

### Important Directories

| Path | Description |
|------|-------------|
| `/var/lib/mysql` | MySQL database files |
| `/var/lib/elasticsearch` | Elasticsearch indices |
| `/var/archivematica/sharedDirectory` | Archivematica shared processing directory |
| `/var/archivematica/storage_service` | Storage Service files |

## Running in Indexless Mode (Without Elasticsearch)

To run Archivematica without Elasticsearch, set the search environment variables to `false`:

```bash
docker run -d \
  --name archivematica \
  --env-file .env \
  -e ARCHIVEMATICA_DASHBOARD_DASHBOARD_SEARCH_ENABLED=false \
  -e ARCHIVEMATICA_MCPSERVER_MCPSERVER_SEARCH_ENABLED=false \
  -e ARCHIVEMATICA_MCPCLIENT_MCPCLIENT_SEARCH_ENABLED=false \
  -p 80:80 \
  -p 8000:8000 \
  archivematica:1.18
```

## Troubleshooting

### Services Not Starting

Check the container logs:

```bash
docker logs archivematica
```

### ClamAV Issues

ClamAV requires time to update its virus definitions. If you see ClamAV errors, wait a few minutes and restart the service:

```bash
docker exec archivematica service clamav-freshclam restart
docker exec archivematica sleep 60
docker exec archivematica service clamav-daemon restart
```

### Gearman Issues

If jobs are not processing, restart Gearman:

```bash
docker exec archivematica service gearman-job-server restart
```

### Check Service Status

```bash
docker exec archivematica service --status-all
```

### View Specific Logs

```bash
# MCP Server logs
docker exec archivematica tail -f /var/log/archivematica/MCPServer/MCPServer.log

# MCP Client logs
docker exec archivematica tail -f /var/log/archivematica/MCPClient/MCPClient.log

# Storage Service logs
docker exec archivematica tail -f /var/log/archivematica/storage-service/storage_service.log

# Dashboard logs
docker exec archivematica tail -f /var/log/archivematica/dashboard/dashboard.log
```

## Security Considerations

- **Change default passwords:** Always modify the database passwords in `.env` before deployment
- **Firewall:** Only expose ports 80 and 8000 externally; keep 3306 and 9200 internal
- **HTTPS:** For production, place a reverse proxy with TLS termination in front of the container
- **Updates:** Rebuild the image periodically to get security updates

## References

- [Archivematica Documentation](https://www.archivematica.org/en/docs/archivematica-1.18/)
- [Ubuntu Installation Guide](https://www.archivematica.org/en/docs/archivematica-1.18/admin-manual/installation-setup/installation/install-ubuntu/)
- [Storage Service Documentation](https://www.archivematica.org/en/docs/storage-service-0.24/)

## License

Archivematica is licensed under the [AGPL-3.0 License](https://github.com/artefactual/archivematica/blob/stable/1.18.x/LICENSE).