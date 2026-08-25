locals {
  chart_files = var.chart_dir != null ? {
    for f in fileset(var.chart_dir, "**") : f => file("${var.chart_dir}/${f}")
  } : null
}

resource "aws_lambda_invocation" "this" {
  function_name   = var.function_name
  lifecycle_scope = "CRUD"

  input = jsonencode({
    type             = var.type
    name             = var.name
    manifest         = var.manifest
    release          = var.release
    chart            = var.chart
    chart_files      = local.chart_files
    repository       = var.repository
    version          = var.chart_version
    namespace        = var.namespace
    create_namespace = var.create_namespace
    values           = var.values
  })
}
