variable "github" {
    description = "GitHub configuration for accessing private repositories."
    type = object({
        username = string
        token    = string
    })
}

variable "server" {
    description = "Server configuration for PostgreSQL instance"
    type = object({
        ssh_server = string
        ssh_port      = number
        ssh_username      = string
        ssh_password     = string
        ssh_private_key_path = string
    })
}

variable "postgres" {
    description = "PostgreSQL cluster configuration"
    type = object({
        username = string
        password = string
        replication_username = string
        replication_password = string
    })
    default = {
        username = "postgres"
        password = "postgres123"
        replication_username = "replicator"
        replication_password = "replicator123"
    }
}

variable "pgbouncer" {
    description = "PgBouncer configuration"
    type = object({
        pool_mode = string
        max_client_conn = number
        default_pool_size = number
        admin_users = string
        stats_users = string
    })
    default = {
        pool_mode = "transaction"
        max_client_conn = 100
        default_pool_size = 25
        admin_users = "postgres"
        stats_users = "postgres"
    }
}

variable "storage" {
    description = "Storage configuration for PostgreSQL"
    type = object({
        size = string
        storage_class = string
    })
    default = {
        size = "8Gi"
        storage_class = "local-path"
    }
}

variable "resources" {
    description = "Resource limits for PostgreSQL and PgBouncer"
    type = object({
        postgresql = object({
            requests_memory = string
            requests_cpu = string
            limits_memory = string
            limits_cpu = string
        })
        pgbouncer = object({
            requests_memory = string
            requests_cpu = string
            limits_memory = string
            limits_cpu = string
        })
    })
    default = {
        postgresql = {
            requests_memory = "256Mi"
            requests_cpu = "250m"
            limits_memory = "1Gi"
            limits_cpu = "1000m"
        }
        pgbouncer = {
            requests_memory = "64Mi"
            requests_cpu = "100m"
            limits_memory = "256Mi"
            limits_cpu = "500m"
        }
    }
}

variable "high_availability" {
    description = "High availability configuration"
    type = object({
        enabled = bool
        replica_count = number
        synchronous_replication = bool
    })
    default = {
        enabled = true
        replica_count = 2
        synchronous_replication = false
    }
}

variable "preserve_postgres_data_on_destroy" {
    description = "Preserve PostgreSQL cluster and data when destroying the deployment. CAUTION: Setting to false will result in permanent data loss."
    type        = bool
    default     = true
}

variable "preserve_postgres_pvcs" {
    description = "Preserve PostgreSQL PersistentVolumeClaims (storage) on destroy. If false, all PostgreSQL data will be permanently deleted."
    type        = bool
    default     = true
}
