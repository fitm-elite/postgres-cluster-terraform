# PostgreSQL Cluster Terraform

Automated PostgreSQL cluster deployment on K3s using Terraform with CloudNativePG operator and PgBouncer connection pooling.

## Prerequisites

- **K3s Kubernetes cluster** installed and running on target server
- SSH access to the target server with sudo privileges
- GitHub account with access to container registries (ghcr.io)

## Architecture

- PostgreSQL cluster using CloudNativePG operator
- PgBouncer connection pooler
- NodePort services for external database access
- High availability with configurable replicas
- Persistent storage

## Configuration

Copy and edit the configuration file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
github = {
  username = "your-github-username"
  token    = "ghp_your_github_personal_access_token"
}

server = {
  ssh_server           = "192.168.1.100"
  ssh_port             = 22
  ssh_username         = "ubuntu"
  ssh_password         = ""
  ssh_private_key_path = "~/.ssh/id_rsa"
}

postgres = {
  username = "postgres"
  password = "secure_password_here"
  replication_username = "replicator"
  replication_password = "replication_password"
}
```

### Key Configuration Parameters

**GitHub**: Username and personal access token for container registry access

**Server**: SSH connection details (IP, port, username, key path)

**PostgreSQL**: Database credentials (username, password, replication credentials)

**PgBouncer** (optional): Pool mode (`transaction`/`session`/`statement`), max connections, pool size

**Storage** (optional): Size (default: 8Gi), storage class (default: local-path)

**High Availability** (optional): Enable HA (default: true), replica count (default: 2)

**Data Preservation** (optional): Preserve data on destroy (default: true), preserve PVCs (default: true)

See [terraform.tfvars.example](terraform.tfvars.example) for all available options.

## Deployment

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy PostgreSQL cluster
terraform apply

# View connection info
terraform output

# Destroy (respects preservation settings)
terraform destroy
```

## Access Information

### NodePort Endpoints

External access from DBMS tools (DBeaver, pgAdmin, etc.):

- **PgBouncer** (recommended): `<server-ip>:30500`
- **PostgreSQL Direct**: `<server-ip>:30501`
- **PostgreSQL Alternative**: `<server-ip>:30502`

### Connection Examples

**Using psql:**
```bash
psql -h <server-ip> -p 30500 -U postgres -d postgres
```

**Connection string:**
```bash
postgresql://postgres:your_password@<server-ip>:30500/postgres
```

**DBMS tools (DBeaver/pgAdmin/DataGrip):**
- Host: Your server IP
- Port: 30500
- Database: postgres
- Username: postgres
- Password: Your configured password

### Internal Kubernetes Access

```bash
# Via PgBouncer
pgbouncer-postgres.postgres.svc.cluster.local:5432

# Direct PostgreSQL
postgresql-postgres.postgres.svc.cluster.local:5432
```

## What Gets Installed

1. System prerequisites (Git, curl, Docker)
2. CloudNativePG operator
3. PostgreSQL cluster in `postgres` namespace
4. PgBouncer connection pooler
5. NodePort services for external access
6. GitHub container registry credentials

## High Availability

When enabled, deploys PostgreSQL with primary + replica instances (default: 3 total). Automatic failover managed by CloudNativePG operator.

## Data Preservation

By default, all data is preserved when running `terraform destroy`. To permanently delete data, set these to `false` in `terraform.tfvars`:

```hcl
preserve_postgres_data_on_destroy = false
preserve_postgres_pvcs = false
```

## Troubleshooting

### K3s Not Found

Install K3s first:
```bash
curl -sfL https://get.k3s.io | sh -
```

### PostgreSQL Cluster Not Ready

Monitor cluster status:
```bash
kubectl get cluster postgresql-postgres -n postgres
kubectl get pods -n postgres
```

### PgBouncer Connection Issues

Check PgBouncer status:
```bash
kubectl get pods -n postgres -l app.kubernetes.io/name=pgbouncer
kubectl logs -n postgres -l app.kubernetes.io/name=pgbouncer
```

### Cannot Connect via NodePort

Check services and firewall:
```bash
kubectl get svc -n postgres
sudo ufw allow 30500/tcp
```

## Security Notes

- **Change default passwords** in production
- Never commit `terraform.tfvars` to version control
- Use SSH key-based authentication
- Configure firewall rules to restrict NodePort access
- Use PgBouncer for connection pooling

## Files

- [main.tf](main.tf) - Main Terraform configuration
- [variables.tf](variables.tf) - Variable definitions
- [postgresql-cluster.yaml](postgresql-cluster.yaml) - PostgreSQL cluster template
- [pgbouncer-manifests.yaml](pgbouncer-manifests.yaml) - PgBouncer deployment
- [ingress.yaml](ingress.yaml) - NodePort services
- [terraform.tfvars.example](terraform.tfvars.example) - Example configuration

## Documentation

- [CloudNativePG](https://cloudnative-pg.io/)
- [PgBouncer](https://www.pgbouncer.org/)
- [K3s](https://docs.k3s.io/)
- [PostgreSQL](https://www.postgresql.org/docs/)
