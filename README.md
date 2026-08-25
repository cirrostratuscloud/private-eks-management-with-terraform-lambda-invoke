# kube_crud

> ⚠️ **Note**: This module was generated with AI assistance and should be reviewed before use in production environments.

A Terraform/OpenTofu module that deploys a Lambda function capable of applying Kubernetes manifests and Helm charts to a private EKS cluster — without internet access.

The Lambda communicates with the EKS API server over the private endpoint using VPC endpoints for EKS and STS. kubectl and helm binaries are bundled into the deployment package at plan time.

## Architecture

```
┌─────────────┐       ┌───────────────────┐       ┌─────────────────┐
│  Terraform  │──────▶│  Lambda (VPC)     │──────▶│  EKS Private    │
│  Invocation │       │  kubectl / helm   │       │  API Endpoint   │
└─────────────┘       └───────────────────┘       └─────────────────┘
                              │
                              ▼
                      ┌───────────────────┐
                      │  VPC Endpoints    │
                      │  (EKS + STS)      │
                      └───────────────────┘
```

## Usage

### 1. Deploy the operator

```hcl
module "kube_crud" {
  source = "./kube_crud"

  name                      = "my-cluster"
  cluster_name              = module.eks.cluster_name
  cluster_security_group_id = module.eks.cluster_primary_security_group_id
  subnet_ids                = module.vpc.private_subnets
  vpc_id                    = module.vpc.vpc_id
  kubectl_version           = "1.36.2"
  helm_version              = "4.2.4"
}
```

### 2. Invoke with manifests

```hcl
module "my_namespace" {
  source = "./kube_crud/modules/invoke"

  function_name = module.kube_crud.function_name
  type          = "manifest"
  name          = "my-namespace"
  manifest = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = "my-app"
    }
  })
}

module "my_configmap" {
  source = "./kube_crud/modules/invoke"

  function_name = module.kube_crud.function_name
  type          = "manifest"
  name          = "my-configmap"
  manifest = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "app-config"
      namespace = "my-app"
    }
    data = {
      key = "value"
    }
  })

  depends_on = [module.my_namespace]
}
```

### 3. Invoke with Helm (local chart)

```hcl
module "my_helm_release" {
  source = "./kube_crud/modules/invoke"

  function_name    = module.kube_crud.function_name
  type             = "helm"
  name             = "my-release"
  release          = "my-release"
  chart            = "my-chart"
  chart_dir        = "${path.module}/charts/my-chart"
  namespace        = "my-app"
  create_namespace = true
  values = yamlencode({
    replicaCount = 2
    image = {
      repository = "nginx"
      tag        = "latest"
    }
  })

  depends_on = [module.my_namespace]
}
```

### 4. Invoke with Helm (remote repository)

Requires internet access (NAT gateway or VPC endpoint to the registry).

```hcl
module "metrics_server" {
  source = "./kube_crud/modules/invoke"

  function_name    = module.kube_crud.function_name
  type             = "helm"
  name             = "metrics-server"
  release          = "metrics-server"
  chart            = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart_version    = "3.12.2"
  namespace        = "kube-system"
  create_namespace = false
}
```

## Ordering

Each invocation is its own module call. Use `depends_on` for explicit ordering:

```hcl
module "namespace" { ... }
module "configmap" { depends_on = [module.namespace] ... }
module "helm"      { depends_on = [module.namespace] ... }
```

## How it works

- **Create/Update**: The Lambda receives the payload and runs `kubectl apply --server-side` (manifests) or `helm upgrade --install` (charts). Both are idempotent.
- **Delete**: When the Terraform resource is destroyed, the Lambda runs `kubectl delete` or `helm uninstall`.
- **Local charts**: When `chart_dir` is set, the invoke module reads all chart files at plan time and passes them inline in the Lambda payload. The handler writes them to `/tmp` and runs helm against the local path. No chart repository needed.

## Requirements

- Private EKS cluster with private endpoint enabled
- VPC endpoints for `eks` and `sts` (for fully private, no-internet operation)
- Lambda subnets must have a route to the EKS API server (same VPC, private subnets)

## Inputs (kube_crud module)

| Name | Description | Default |
|------|-------------|---------|
| `name` | Name prefix for resources | - |
| `cluster_name` | EKS cluster name | - |
| `cluster_security_group_id` | EKS-managed cluster security group ID | - |
| `subnet_ids` | Private subnet IDs for the Lambda | - |
| `vpc_id` | VPC ID | - |
| `kubectl_version` | kubectl binary version | `1.36.2` |
| `helm_version` | Helm binary version | `4.2.4` |
| `runtime` | Lambda Python runtime | `python3.14` |
| `architecture` | Lambda architecture (`x86_64` or `arm64`) | `x86_64` |
| `memory_size` | Lambda memory (MB) | `512` |
| `timeout` | Lambda timeout (seconds) | `900` |

## Inputs (invoke submodule)

| Name | Description | Default |
|------|-------------|---------|
| `function_name` | Lambda function name from kube_crud output | - |
| `type` | `manifest` or `helm` | - |
| `name` | Logical name for this invocation | - |
| `manifest` | YAML manifest content (for manifests) | `""` |
| `release` | Helm release name | `""` |
| `chart` | Helm chart name | `""` |
| `chart_dir` | Local chart directory path | `null` |
| `repository` | Chart repository URL | `null` |
| `chart_version` | Chart version | `null` |
| `namespace` | Kubernetes namespace | `"default"` |
| `create_namespace` | Let helm create the namespace | `true` |
| `values` | Helm values YAML string | `""` |

## Outputs (kube_crud module)

| Name | Description |
|------|-------------|
| `function_name` | Lambda function name |
| `function_arn` | Lambda function ARN |
| `role_arn` | Lambda IAM role ARN (has cluster-admin) |
| `security_group_id` | Lambda security group ID |
