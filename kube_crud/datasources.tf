data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

resource "terraform_data" "binaries" {
  triggers_replace = {
    kubectl      = var.kubectl_version
    helm         = var.helm_version
    architecture = var.architecture
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      ARCH="${var.architecture == "arm64" ? "arm64" : "amd64"}"
      mkdir -p ${path.module}/src/bin
      curl -sL "https://dl.k8s.io/release/v${var.kubectl_version}/bin/linux/$ARCH/kubectl" -o ${path.module}/src/bin/kubectl
      chmod +x ${path.module}/src/bin/kubectl
      curl -sL "https://get.helm.sh/helm-v${var.helm_version}-linux-$ARCH.tar.gz" | tar -xz --strip-components=1 -C ${path.module}/src/bin linux-$ARCH/helm
      chmod +x ${path.module}/src/bin/helm
    EOT
  }
}

data "archive_file" "handler" {
  type        = "zip"
  source_dir  = local.src_dir
  output_path = "${path.module}/.build/handler-${local.src_hash}.zip"

  depends_on = [terraform_data.binaries]
}
