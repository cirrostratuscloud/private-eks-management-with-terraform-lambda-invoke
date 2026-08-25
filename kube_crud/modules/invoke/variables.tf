variable "function_name" {
  description = "Lambda function name to invoke."
  type        = string
}

variable "type" {
  description = "Invocation type: manifest or helm."
  type        = string

  validation {
    condition     = contains(["manifest", "helm"], var.type)
    error_message = "Type must be manifest or helm."
  }
}

variable "name" {
  description = "Logical name for this invocation."
  type        = string
}

variable "manifest" {
  description = "Raw YAML manifest content (for type=manifest)."
  type        = string
  default     = ""
}

variable "release" {
  description = "Helm release name (for type=helm)."
  type        = string
  default     = ""
}

variable "chart" {
  description = "Helm chart name or path (for type=helm)."
  type        = string
  default     = ""
}

variable "chart_dir" {
  description = "Local path to a chart directory. Files are read and passed inline to the Lambda."
  type        = string
  default     = null
}

variable "repository" {
  description = "Helm chart repository URL (for type=helm)."
  type        = string
  default     = null
}

variable "chart_version" {
  description = "Helm chart version (for type=helm)."
  type        = string
  default     = null
}

variable "namespace" {
  description = "Kubernetes namespace (for type=helm)."
  type        = string
  default     = "default"
}

variable "create_namespace" {
  description = "Whether helm should create the namespace."
  type        = bool
  default     = true
}

variable "values" {
  description = "Helm values YAML string (for type=helm)."
  type        = string
  default     = ""
}
