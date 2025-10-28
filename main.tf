terraform {
    required_providers {
        null = {
            source  = "hashicorp/null"
            version = ">= 3.1"
        }
    }

    required_version = ">= 1.3.0"
}

resource "null_resource" "preflight" {
    triggers = {
        always_run = timestamp()
    }

    connection {
        type = "ssh"
        host = var.server.ssh_server
        port = var.server.ssh_port
        user = var.server.ssh_username
        private_key = file(var.server.ssh_private_key_path)
        password = var.server.ssh_password
        timeout = "2m"
    }

    provisioner "remote-exec" {
        inline = [
            "sudo apt-get update && sudo apt-get upgrade -y",
            "sudo apt-get install -y git curl apt-transport-https ca-certificates software-properties-common",
        ]
    }

    provisioner "remote-exec" {
        inline = [
            "if [ -z \"$(git config --global --get user.name)\" ]; then",
            "    echo 'Setting Git user name...'",
            "    git config --global user.name '${var.github.username}'",
            "else",
            "    echo 'Git user name already configured: '$(git config --global --get user.name)",
            "fi",

            "if [ -z \"$(git config --global --get user.email)\" ]; then",
            "    echo 'Setting Git user email...'",
            "    git config --global user.email '${var.github.username}@users.noreply.github.com'",
            "else",
            "    echo 'Git user email already configured: '$(git config --global --get user.email)",
            "fi",

            "if [ -z \"$(git config --global --get credential.helper)\" ]; then",
            "    echo 'Setting Git credential helper...'",
            "    git config --global credential.helper store",
            "else",
            "    echo 'Git credential helper already configured: '$(git config --global --get credential.helper)",
            "fi",

            "if [ ! -f ~/.git-credentials ]; then",
            "    echo 'Setting up Git credentials...'",
            "    echo 'https://${var.github.username}:${var.github.token}@github.com' > ~/.git-credentials",
            "    chmod 600 ~/.git-credentials",
            "else",
            "    echo 'Git credentials file already exists'",
            "    chmod 600 ~/.git-credentials",
            "fi"
        ]
    }

    provisioner "remote-exec" {
        inline = [
            "if ! command -v docker >/dev/null 2>&1 && ! which docker >/dev/null 2>&1 && ! [ -x /usr/bin/docker ] && ! [ -x /usr/local/bin/docker ]; then",

            "   echo 'Docker not found. Installing Docker...'",
            "   for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done",

            "   sudo apt-get update",
            "   sudo apt-get install -y ca-certificates curl",

            "   sudo mkdir -p /etc/apt/keyrings",
            "   sudo install -m 0755 -d /etc/apt/keyrings",
            "   sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc",
            "   sudo chmod a+r /etc/apt/keyrings/docker.asc",

            "   echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
            "   sudo apt-get update",

            "   sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",

            "   sudo groupadd docker",
            "   sudo usermod -aG docker $USER",

            "   sudo systemctl start docker",
            "   sudo systemctl enable docker",

            "   echo 'Docker installation completed successfully'",
            "else",
            "   echo 'Docker is already installed. Skipping installation.'",
            "   docker --version",
            "fi"
        ]
    }

    provisioner "remote-exec" {
        inline = [
            "echo 'Checking if Kubernetes (K3s) is installed and running...'",

            "if ! command -v k3s >/dev/null 2>&1 && ! [ -f /usr/local/bin/k3s ]; then",
            "    echo 'ERROR: Kubernetes (K3s) is not installed on this system'",
            "    echo 'Please install K3s before deploying PostgreSQL'",
            "    echo 'Run the kubernetes terraform module first'",
            "    exit 1",
            "fi",

            "if ! systemctl is-active --quiet k3s 2>/dev/null && ! systemctl is-active --quiet k3s-agent 2>/dev/null; then",
            "    echo 'ERROR: Kubernetes (K3s) is installed but not running'",
            "    echo 'Please start the K3s service before deploying PostgreSQL'",
            "    echo 'Run: sudo systemctl start k3s (or k3s-agent for agent nodes)'",
            "    exit 1",
            "fi",

            "echo 'Kubernetes (K3s) is installed and running.'",

            "echo 'Checking Kubernetes cluster access...'",
            "export KUBECONFIG=~/.kube/config",
            "if [ ! -f ~/.kube/config ]; then",
            "    echo 'Creating kubeconfig from K3s...'",
            "    mkdir -p ~/.kube",
            "    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config",
            "    sudo chown $(id -u):$(id -g) ~/.kube/config",
            "    chmod 600 ~/.kube/config",
            "    echo 'Kubeconfig created successfully'",
            "fi",

            "if ! kubectl get nodes >/dev/null 2>&1; then",
            "    echo 'WARNING: Cannot access Kubernetes cluster with current kubeconfig'",
            "    echo 'Attempting to refresh kubeconfig from K3s...'",
            "    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config",
            "    sudo chown $(id -u):$(id -g) ~/.kube/config",
            "    chmod 600 ~/.kube/config",
            "    if ! kubectl get nodes >/dev/null 2>&1; then",
            "        echo 'ERROR: Still cannot access Kubernetes cluster after refresh'",
            "        echo 'Please check K3s installation and permissions'",
            "        exit 1",
            "    fi",
            "fi",

            "echo 'Kubernetes validation completed. Proceeding with PostgreSQL deployment...'",
        ]
    }
}

locals {
    postgres_clusters = {
        "postgres" = {
            namespace = "postgres"
            database = "postgres"
            username = var.postgres.username
            password = var.postgres.password
        }
    }
}

resource "null_resource" "postgres_initialization" {
    depends_on = [ null_resource.preflight ]

    for_each = local.postgres_clusters

    connection {
        type = "ssh"
        host = var.server.ssh_server
        port = var.server.ssh_port
        user = var.server.ssh_username
        private_key = file(var.server.ssh_private_key_path)
        password = var.server.ssh_password
        timeout = "2m"
    }

    provisioner "file" {
        source = "postgresql-cluster.yaml"
        destination = "/tmp/postgresql-cluster-${each.key}.yaml"
    }

    provisioner "file" {
        source = "pgbouncer-manifests.yaml"
        destination = "/tmp/pgbouncer-manifests-${each.key}.yaml"
    }

    provisioner "file" {
        source = "ingress.yaml"
        destination = "/tmp/ingress-${each.key}.yaml"
    }

    provisioner "remote-exec" {
        inline = [
            "echo 'Setting up kubeconfig for PostgreSQL installation...'",
            "export KUBECONFIG=~/.kube/config",

            "echo 'Setting up PostgreSQL cluster for ${each.key}...'",
            "echo 'Checking if PostgreSQL is already deployed in ${each.value.namespace}...'",
            "echo 'First, checking for existing helm releases...'",
            "if helm --kubeconfig ~/.kube/config list -n ${each.value.namespace} | grep -q postgresql-${each.key}; then",
            "    echo 'WARNING: PostgreSQL helm release already exists for ${each.key}'",
            "    echo 'Uninstalling existing release...'",
            "    helm --kubeconfig ~/.kube/config uninstall postgresql-${each.key} -n ${each.value.namespace} || true",
            "    echo 'Waiting for cleanup...'",
            "    sleep 15",
            "fi",

            "if helm --kubeconfig ~/.kube/config list -n ${each.value.namespace} | grep -q pgbouncer-${each.key}; then",
            "    echo 'WARNING: PgBouncer helm release already exists for ${each.key}'",
            "    echo 'Uninstalling existing release...'",
            "    helm --kubeconfig ~/.kube/config uninstall pgbouncer-${each.key} -n ${each.value.namespace} || true",
            "    echo 'Waiting for cleanup...'",
            "    sleep 10",
            "fi",

            "echo 'Installing CloudNativePG operator...'",
            "if ! kubectl --kubeconfig ~/.kube/config get crd clusters.postgresql.cnpg.io >/dev/null 2>&1; then",
            "    echo 'CloudNativePG operator not found, installing...'",
            "    kubectl --kubeconfig ~/.kube/config apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.21/releases/cnpg-1.21.1.yaml",
            "    echo 'Waiting for operator to be ready...'",
            "    kubectl --kubeconfig ~/.kube/config wait --for=condition=Available deployment/cnpg-controller-manager -n cnpg-system --timeout=300s",
            "else",
            "    echo 'CloudNativePG operator already installed'",
            "fi",

            "echo 'Checking if ${each.value.namespace} namespace exists...'",
            "if ! kubectl --kubeconfig ~/.kube/config get namespace ${each.value.namespace} >/dev/null 2>&1; then",
            "    echo 'Creating ${each.value.namespace} namespace...'",
            "    kubectl --kubeconfig ~/.kube/config create namespace ${each.value.namespace}",
            "    echo '${each.value.namespace} namespace created successfully'",
            "else",
            "    echo '${each.value.namespace} namespace already exists'",
            "fi",
            "",
            "echo 'Creating GitHub Container Registry (ghcr.io) image pull secret in ${each.value.namespace}...'",
            "kubectl --kubeconfig ~/.kube/config create secret docker-registry ghcr-io-secret \\",
            "  --namespace=${each.value.namespace} \\",
            "  --docker-server=ghcr.io \\",
            "  --docker-username='${var.github.username}' \\",
            "  --docker-password='${var.github.token}' \\",
            "  --docker-email='${var.github.username}@users.noreply.github.com' \\",
            "  --dry-run=client -o yaml | kubectl --kubeconfig ~/.kube/config apply -f -",
            "echo 'GitHub Container Registry secret created successfully in ${each.value.namespace} namespace'",
            "",
            "if kubectl --kubeconfig ~/.kube/config get namespace ${each.value.namespace} >/dev/null 2>&1 && [ \"$(kubectl get all -n ${each.value.namespace} --no-headers 2>/dev/null | wc -l)\" -gt 0 ]; then",
            "    echo 'Namespace ${each.value.namespace} has existing resources'",
            "    echo 'Cleaning up existing resources in ${each.value.namespace}...'",
            "    ",
            "    echo 'Deleting existing PostgreSQL clusters...'",
            "    echo 'Deleting existing PostgreSQL clusters...'",
            "    kubectl --kubeconfig ~/.kube/config delete cluster postgresql-${each.key} -n ${each.value.namespace} --ignore-not-found=true",
            "    ",
            "    echo 'Deleting existing PgBouncer deployments...'",
            "    kubectl --kubeconfig ~/.kube/config delete deployment pgbouncer-${each.key} -n ${each.value.namespace} --ignore-not-found=true",
            "    ",
            "    echo 'Deleting existing services...'",
            "    kubectl --kubeconfig ~/.kube/config delete svc postgresql-${each.key}-rw -n ${each.value.namespace} --ignore-not-found=true",
            "    kubectl --kubeconfig ~/.kube/config delete svc postgresql-${each.key}-ro -n ${each.value.namespace} --ignore-not-found=true",
            "    kubectl --kubeconfig ~/.kube/config delete svc postgresql-${each.key} -n ${each.value.namespace} --ignore-not-found=true",
            "    kubectl --kubeconfig ~/.kube/config delete svc pgbouncer-${each.key} -n ${each.value.namespace} --ignore-not-found=true",
            "    kubectl --kubeconfig ~/.kube/config delete svc postgres-${each.key}-nodeport -n ${each.value.namespace} --ignore-not-found=true",
            "    kubectl --kubeconfig ~/.kube/config delete svc postgres-${each.key}-postgresql-nodeport -n ${each.value.namespace} --ignore-not-found=true",
            "    ",
            "    echo 'Deleting existing secrets...'",
            "    kubectl --kubeconfig ~/.kube/config delete secret postgresql-${each.key}-superuser -n ${each.value.namespace} --ignore-not-found=true",
            "    kubectl --kubeconfig ~/.kube/config delete secret pgbouncer-${each.key}-secret -n ${each.value.namespace} --ignore-not-found=true",
            "    ",
            "    echo 'Deleting existing ConfigMaps...'",
            "    kubectl --kubeconfig ~/.kube/config delete configmap postgres-${each.key}-connection-info -n ${each.value.namespace} --ignore-not-found=true",
            "    ",
            "    echo 'Waiting for resources to be fully deleted...'",
            "    sleep 30",
            "    ",
            "    echo 'Verifying resources are deleted...'",
            "    kubectl get cluster postgresql-${each.key} -n ${each.value.namespace} 2>/dev/null && echo 'WARNING: Cluster still exists' || echo 'Cluster deleted'",
            "    kubectl get svc postgresql-${each.key}-rw -n ${each.value.namespace} 2>/dev/null && echo 'WARNING: RW service still exists' || echo 'RW service deleted'",
            "    kubectl get svc postgresql-${each.key}-ro -n ${each.value.namespace} 2>/dev/null && echo 'WARNING: RO service still exists' || echo 'RO service deleted'",
            "    ",
            "    echo 'Cleanup completed'",
            "fi",

            "mkdir -p ~/postgres-${each.key}",
            "sudo mv /tmp/postgresql-cluster-${each.key}.yaml ~/postgres-${each.key}/postgresql-cluster.yaml",
            "sudo mv /tmp/pgbouncer-manifests-${each.key}.yaml ~/postgres-${each.key}/pgbouncer-manifests.yaml",
            "sudo mv /tmp/ingress-${each.key}.yaml ~/postgres-${each.key}/ingress.yaml",

            "cd ~/postgres-${each.key}",

            "echo 'Customizing PostgreSQL cluster manifest for ${each.key}...'",
            "sed -i 's/\\$${cluster_name}/${each.key}/g' postgresql-cluster.yaml",
            "sed -i 's/\\$${namespace}/${each.value.namespace}/g' postgresql-cluster.yaml",
            "sed -i 's/\\$${database_name}/${each.value.database}/g' postgresql-cluster.yaml",
            "sed -i 's/\\$${postgres_password}/${each.value.password}/g' postgresql-cluster.yaml",
            "sed -i 's/\\$${postgres_username}/${each.value.username}/g' postgresql-cluster.yaml",
            "sed -i 's/\\$${instances}/${var.high_availability.enabled ? var.high_availability.replica_count + 1 : 1}/g' postgresql-cluster.yaml",
            "sed -i 's/\\$${storage_size}/${var.storage.size}/g' postgresql-cluster.yaml",
            "sed -i 's/\\$${storage_class}/${var.storage.storage_class}/g' postgresql-cluster.yaml",
            "sed -i 's/\\$${postgresql_limits_memory}/${var.resources.postgresql.limits_memory}/g' postgresql-cluster.yaml",
            "sed -i 's/\\$${postgresql_limits_cpu}/${var.resources.postgresql.limits_cpu}/g' postgresql-cluster.yaml",
            "sed -i 's/\\$${postgresql_requests_memory}/${var.resources.postgresql.requests_memory}/g' postgresql-cluster.yaml",
            "sed -i 's/\\$${postgresql_requests_cpu}/${var.resources.postgresql.requests_cpu}/g' postgresql-cluster.yaml",


            "echo 'Deploying PostgreSQL cluster for ${each.key}...'",
            "kubectl --kubeconfig ~/.kube/config apply -f postgresql-cluster.yaml",

            "echo 'Waiting for PostgreSQL ${each.key} cluster to be ready...'",
            "kubectl --kubeconfig ~/.kube/config wait --for=condition=Ready cluster/postgresql-${each.key} -n ${each.value.namespace} --timeout=600s",

            "echo 'Customizing PgBouncer manifests for ${each.key}...'",
            "sed -i 's/\\$${cluster_name}/${each.key}/g' pgbouncer-manifests.yaml",
            "sed -i 's/\\$${namespace}/${each.value.namespace}/g' pgbouncer-manifests.yaml",
            "sed -i 's/\\$${postgres_host}/postgresql-${each.key}-rw.${each.value.namespace}.svc.cluster.local/g' pgbouncer-manifests.yaml",
            "sed -i 's/\\$${postgres_port}/\"5432\"/g' pgbouncer-manifests.yaml",
            "sed -i 's/\\$${postgres_username}/${each.value.username}/g' pgbouncer-manifests.yaml",
            "sed -i 's/\\$${postgres_password}/${each.value.password}/g' pgbouncer-manifests.yaml",
            "sed -i 's/\\$${postgres_database}/${each.value.database}/g' pgbouncer-manifests.yaml",
            "sed -i 's/\\$${pool_mode}/${var.pgbouncer.pool_mode}/g' pgbouncer-manifests.yaml",
            "sed -i 's/\\$${max_client_conn}/${var.pgbouncer.max_client_conn}/g' pgbouncer-manifests.yaml",
            "sed -i 's/\\$${default_pool_size}/${var.pgbouncer.default_pool_size}/g' pgbouncer-manifests.yaml",
            "sed -i 's/\\$${admin_users}/${var.pgbouncer.admin_users}/g' pgbouncer-manifests.yaml",
            "sed -i 's/\\$${stats_users}/${var.pgbouncer.stats_users}/g' pgbouncer-manifests.yaml",
            "sed -i 's/\\$${pgbouncer_limits_memory}/${var.resources.pgbouncer.limits_memory}/g' pgbouncer-manifests.yaml",
            "sed -i 's/\\$${pgbouncer_limits_cpu}/${var.resources.pgbouncer.limits_cpu}/g' pgbouncer-manifests.yaml",
            "sed -i 's/\\$${pgbouncer_requests_memory}/${var.resources.pgbouncer.requests_memory}/g' pgbouncer-manifests.yaml",
            "sed -i 's/\\$${pgbouncer_requests_cpu}/${var.resources.pgbouncer.requests_cpu}/g' pgbouncer-manifests.yaml",

            "echo 'All PgBouncer variables have been configured for ${each.key}...'",

            "echo 'Deploying PgBouncer for ${each.key}...'",
            "kubectl --kubeconfig ~/.kube/config apply -f pgbouncer-manifests.yaml",

            "echo 'Waiting for PgBouncer ${each.key} to be ready...'",
            "kubectl --kubeconfig ~/.kube/config wait --for=condition=ready pod -l app.kubernetes.io/name=pgbouncer -n ${each.value.namespace} --timeout=180s",

            "echo 'Checking PostgreSQL password status for ${each.key}...'",
            "echo 'Waiting for PostgreSQL primary pod to be ready...'",
            "kubectl --kubeconfig ~/.kube/config wait --for=condition=ready pod -l cnpg.io/cluster=postgresql-${each.key},role=primary -n ${each.value.namespace} --timeout=300s",
            "POD_NAME=$(kubectl --kubeconfig ~/.kube/config get pods -n ${each.value.namespace} -l cnpg.io/cluster=postgresql-${each.key},role=primary -o jsonpath='{.items[0].metadata.name}')",
            "echo \"Checking if password is already set for ${each.value.username} user in pod: $POD_NAME\"",
            "echo 'Waiting for PostgreSQL to be fully initialized...'",
            "sleep 10",
            "PASSWORD_CHECK=$(kubectl --kubeconfig ~/.kube/config exec -n ${each.value.namespace} \"$POD_NAME\" -- psql -U ${each.value.username} -d postgres -t -c \"SELECT rolpassword IS NOT NULL FROM pg_authid WHERE rolname='${each.value.username}';\" 2>/dev/null | tr -d ' ' || echo 'f')",
            "if [ \"$PASSWORD_CHECK\" = \"t\" ]; then",
            "    echo 'Password already set for ${each.key}, skipping password reset to prevent disconnections'",
            "else",
            "    echo 'Password not set, setting now with SCRAM-SHA-256 encryption...'",
            "    kubectl --kubeconfig ~/.kube/config exec -n ${each.value.namespace} \"$POD_NAME\" -- psql -U ${each.value.username} -d postgres -c \"ALTER USER ${each.value.username} WITH PASSWORD '${each.value.password}';\" || true",
            "fi",
            "echo 'Verifying password was set correctly...'",
            "PASSWORD_CHECK=$(kubectl --kubeconfig ~/.kube/config exec -n ${each.value.namespace} \"$POD_NAME\" -- psql -U ${each.value.username} -d postgres -t -c \"SELECT rolpassword IS NOT NULL FROM pg_authid WHERE rolname='${each.value.username}';\" | tr -d ' ')",
            "if [ \"$PASSWORD_CHECK\" = \"t\" ]; then",
            "    echo 'PostgreSQL password set successfully for ${each.key}'",
            "else",
            "    echo 'WARNING: Password may not have been set correctly for ${each.key}'",
            "    echo 'Retrying password setup...'",
            "    sleep 5",
            "    kubectl --kubeconfig ~/.kube/config exec -n ${each.value.namespace} \"$POD_NAME\" -- psql -U ${each.value.username} -d postgres -c \"ALTER USER ${each.value.username} WITH PASSWORD '${each.value.password}';\"",
            "    PASSWORD_CHECK=$(kubectl --kubeconfig ~/.kube/config exec -n ${each.value.namespace} \"$POD_NAME\" -- psql -U ${each.value.username} -d postgres -t -c \"SELECT rolpassword IS NOT NULL FROM pg_authid WHERE rolname='${each.value.username}';\" | tr -d ' ')",
            "    if [ \"$PASSWORD_CHECK\" = \"t\" ]; then",
            "        echo 'Password set successfully on retry'",
            "    else",
            "        echo 'ERROR: Failed to set password after retry!'",
            "        exit 1",
            "    fi",
            "fi",
            "echo 'Verifying SCRAM-SHA-256 authentication...'",
            "SCRAM_CHECK=$(kubectl --kubeconfig ~/.kube/config exec -n ${each.value.namespace} \"$POD_NAME\" -- psql -U ${each.value.username} -d postgres -t -c \"SELECT rolpassword LIKE 'SCRAM-SHA-256\\$%' FROM pg_authid WHERE rolname='${each.value.username}';\" | tr -d ' ')",
            "if [ \"$SCRAM_CHECK\" = \"t\" ]; then",
            "    echo 'Password is correctly stored with SCRAM-SHA-256 encryption'",
            "else",
            "    echo 'WARNING: Password is not using SCRAM-SHA-256 encryption!'",
            "fi",
            "echo 'Testing authentication from PgBouncer pod...'",
            "sleep 5",
            "PGBOUNCER_POD=$(kubectl --kubeconfig ~/.kube/config get pods -n ${each.value.namespace} -l app.kubernetes.io/name=pgbouncer -o jsonpath='{.items[0].metadata.name}')",
            "if [ -n \"$PGBOUNCER_POD\" ]; then",
            "    echo \"Testing connection from PgBouncer pod: $PGBOUNCER_POD\"",
            "    kubectl --kubeconfig ~/.kube/config exec -n ${each.value.namespace} \"$PGBOUNCER_POD\" -- env PGPASSWORD='${each.value.password}' psql -h postgresql-${each.key}-rw.${each.value.namespace}.svc.cluster.local -U ${each.value.username} -d ${each.value.database} -c 'SELECT 1;' && echo 'PgBouncer can authenticate to PostgreSQL successfully!' || echo 'WARNING: PgBouncer authentication test failed'",
            "else",
            "    echo 'PgBouncer pod not found, skipping authentication test'",
            "fi",

            "echo 'Customizing ingress for ${each.key}...'",
            "sed -i 's/\\$${cluster_name}/${each.key}/g' ingress.yaml",
            "sed -i 's/\\$${namespace}/${each.value.namespace}/g' ingress.yaml",
            "sed -i 's/\\$${server_ip}/${var.server.ssh_server}/g' ingress.yaml",
            "sed -i 's/\\$${database_name}/${each.value.database}/g' ingress.yaml",
            "sed -i 's/\\$${pgbouncer_nodeport}/30500/g' ingress.yaml",
            "sed -i 's/\\$${postgresql_direct_nodeport}/30501/g' ingress.yaml",
            "sed -i 's/\\$${postgresql_nodeport}/30502/g' ingress.yaml",

            "echo 'Applying ingress configuration for ${each.key}...'",
            "kubectl --kubeconfig ~/.kube/config apply -f ingress.yaml",

            "echo 'PostgreSQL cluster ${each.key} deployed successfully!'"
        ]
    }
}

resource "null_resource" "postgres_termination" {
    for_each = local.postgres_clusters

    triggers = {
        initialization_id = null_resource.postgres_initialization[each.key].id
        ssh_server = var.server.ssh_server
        ssh_port = var.server.ssh_port
        ssh_username = var.server.ssh_username
        ssh_password = var.server.ssh_password
        ssh_private_key_path = var.server.ssh_private_key_path
        namespace = each.value.namespace
        cluster_name = each.key
        preserve_postgres_data_on_destroy = var.preserve_postgres_data_on_destroy
        preserve_postgres_pvcs = var.preserve_postgres_pvcs
    }

    connection {
        type = "ssh"
        host = self.triggers.ssh_server
        port = self.triggers.ssh_port
        user = self.triggers.ssh_username
        private_key = file(self.triggers.ssh_private_key_path)
        password = self.triggers.ssh_password
        timeout = "2m"
    }

    provisioner "remote-exec" {
        when = destroy
        inline = [
            "echo 'Setting up kubeconfig for PostgreSQL removal...'",
            "export KUBECONFIG=~/.kube/config",

            "echo 'PostgreSQL data preservation settings:'",
            "echo '  preserve_postgres_data_on_destroy: ${lookup(self.triggers, "preserve_postgres_data_on_destroy", "true")}'",
            "echo '  preserve_postgres_pvcs: ${lookup(self.triggers, "preserve_postgres_pvcs", "true")}'",
            "echo ''",

            "echo 'Checking if PostgreSQL cluster ${self.triggers.cluster_name} is deployed...'",
            "if kubectl --kubeconfig ~/.kube/config get cluster postgresql-${self.triggers.cluster_name} -n ${self.triggers.namespace} >/dev/null 2>&1; then",
            "    ",
            "    # Check preservation settings",
            "    if [ '${lookup(self.triggers, "preserve_postgres_data_on_destroy", "true")}' = 'false' ]; then",
            "        echo 'WARNING: preserve_postgres_data_on_destroy is false - PostgreSQL data will be deleted'",
            "        echo 'Deleting PostgreSQL cluster...'",
            "        kubectl --kubeconfig ~/.kube/config delete cluster postgresql-${self.triggers.cluster_name} -n ${self.triggers.namespace}",
            "        kubectl --kubeconfig ~/.kube/config delete secret postgresql-${self.triggers.cluster_name}-superuser -n ${self.triggers.namespace} || true",
            "        echo 'PostgreSQL cluster deleted successfully'",
            "    else",
            "        echo 'Preserving PostgreSQL cluster - only stopping pods'",
            "        kubectl --kubeconfig ~/.kube/config scale cluster postgresql-${self.triggers.cluster_name} --replicas=0 -n ${self.triggers.namespace} || true",
            "        echo 'PostgreSQL cluster scaled down - data preserved'",
            "    fi",
            "else",
            "    echo 'No PostgreSQL cluster found for ${self.triggers.cluster_name}. Skipping deletion.'",
            "fi",

            "if kubectl --kubeconfig ~/.kube/config get deployment pgbouncer-${self.triggers.cluster_name} -n ${self.triggers.namespace} >/dev/null 2>&1; then",
            "    echo 'Deleting PgBouncer deployment for ${self.triggers.cluster_name}...'",
            "    kubectl --kubeconfig ~/.kube/config delete deployment pgbouncer-${self.triggers.cluster_name} -n ${self.triggers.namespace}",
            "    kubectl --kubeconfig ~/.kube/config delete service pgbouncer-${self.triggers.cluster_name} -n ${self.triggers.namespace}",
            "    kubectl --kubeconfig ~/.kube/config delete secret pgbouncer-${self.triggers.cluster_name}-secret -n ${self.triggers.namespace}",
            "    echo 'PgBouncer deployment for ${self.triggers.cluster_name} deleted successfully'",
            "else",
            "    echo 'No PgBouncer deployment found for ${self.triggers.cluster_name}. Skipping deletion.'",
            "fi",

            "echo 'Cleaning up remaining resources for ${self.triggers.cluster_name}...'",
            "kubectl --kubeconfig ~/.kube/config delete all --all -n ${self.triggers.namespace} || true",
            "",
            "# Handle PVC deletion based on preservation settings",
            "if [ '${lookup(self.triggers, "preserve_postgres_data_on_destroy", "true")}' = 'false' ] || [ '${lookup(self.triggers, "preserve_postgres_pvcs", "true")}' = 'false' ]; then",
            "    echo 'CRITICAL WARNING: Deleting all PostgreSQL PVCs - ALL DATA WILL BE PERMANENTLY LOST!'",
            "    kubectl --kubeconfig ~/.kube/config delete pvc --all -n ${self.triggers.namespace} || true",
            "    echo 'Deleting namespace ${self.triggers.namespace}...'",
            "    kubectl --kubeconfig ~/.kube/config delete namespace ${self.triggers.namespace} || true",
            "else",
            "    echo 'Preserving PostgreSQL PVCs for ${self.triggers.cluster_name}'",
            "    REMAINING_PVCS=$(kubectl get pvc -n ${self.triggers.namespace} --no-headers 2>/dev/null | wc -l)",
            "    if [ \"$REMAINING_PVCS\" -gt 0 ]; then",
            "        echo \"INFO: $REMAINING_PVCS PostgreSQL persistent volume(s) preserved\"",
            "        kubectl get pvc -n ${self.triggers.namespace}",
            "        echo 'IMPORTANT: Namespace ${self.triggers.namespace} preserved due to PVCs'",
            "        echo 'Data will be available when PostgreSQL cluster is redeployed'",
            "        echo 'To manually delete all data: kubectl delete namespace ${self.triggers.namespace}'",
            "    else",
            "        echo 'No PVCs found. Deleting namespace...'",
            "        kubectl --kubeconfig ~/.kube/config delete namespace ${self.triggers.namespace} || true",
            "    fi",
            "fi",
            "",
            "echo 'PostgreSQL cluster ${self.triggers.cluster_name} cleanup completed'"
        ]
        on_failure = continue
    }
}

output "postgresql_endpoints" {
    description = "PostgreSQL cluster endpoints"
    value = {
        for k, v in local.postgres_clusters : k => "postgresql-${k}.${v.namespace}.svc.cluster.local:5432"
    }
}

output "pgbouncer_endpoints" {
    description = "PgBouncer connection pooler endpoints"
    value = {
        for k, v in local.postgres_clusters : k => "pgbouncer-${k}.${v.namespace}.svc.cluster.local:5432"
    }
}

output "namespaces" {
    description = "Kubernetes namespaces for PostgreSQL clusters"
    value = {
        for k, v in local.postgres_clusters : k => v.namespace
    }
}

output "databases" {
    description = "Database names for each cluster"
    value = {
        for k, v in local.postgres_clusters : k => v.database
    }
}

output "nodeport_endpoints" {
    description = "External NodePort endpoints for DBMS connections"
    value = {
        for k, v in local.postgres_clusters : k => {
            pgbouncer_nodeport = "${var.server.ssh_server}:30500"
            postgresql_nodeport = "${var.server.ssh_server}:30502"
            postgresql_direct_nodeport = "${var.server.ssh_server}:30501"
        }
    }
}

output "cluster_info" {
    description = "Complete cluster information"
    value = {
        for k, v in local.postgres_clusters : k => {
            postgresql_endpoint = "postgresql-${k}.${v.namespace}.svc.cluster.local:5432"
            pgbouncer_endpoint = "pgbouncer-${k}.${v.namespace}.svc.cluster.local:5432"
            pgbouncer_nodeport = "${var.server.ssh_server}:30500"
            postgresql_nodeport = "${var.server.ssh_server}:30502"
            namespace = v.namespace
            database = v.database
            username = v.username
        }
    }
    sensitive = true
}
