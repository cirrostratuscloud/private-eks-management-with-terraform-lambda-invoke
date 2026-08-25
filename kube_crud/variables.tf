variable "name" {
  description = "Name prefix for bootstrap resources (typically the cluster name)."
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "kubectl_version" {
  description = "kubectl binary version to download (e.g. 1.36.2)."
  type        = string
  default     = "1.36.2"
}

variable "helm_version" {
  description = "Helm binary version to download (e.g. 4.2.4)."
  type        = string
  default     = "4.2.4"
}

variable "runtime" {
  description = "Lambda runtime. Must be a Python runtime."
  type        = string
  default     = "python3.14"

  validation {
    condition     = can(regex("^python3\\.", var.runtime))
    error_message = "Runtime must be a Python runtime (e.g. python3.12)."
  }
}

variable "architecture" {
  description = "Lambda architecture. Valid values: x86_64, arm64."
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "Architecture must be x86_64 or arm64."
  }
}

variable "cluster_security_group_id" {
  description = "EKS-managed cluster security group ID. The Lambda security group is granted inbound 443 access to the API server via this group."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs the Lambda runs in (must have egress for chart/image pulls and a route to the EKS private endpoint)."
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID the Lambda runs in."
  type        = string
}

variable "memory_size" {
  description = "Lambda memory (MB)."
  type        = number
  default     = 512
}

variable "timeout" {
  description = "Lambda timeout (seconds). Max 900."
  type        = number
  default     = 900
}

variable "log_retention_days" {
  description = "CloudWatch log retention for the Lambda."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to bootstrap resources."
  type        = map(string)
  default     = {}
}
