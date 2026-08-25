locals {
  src_dir = "${path.module}/src"

  # Hash computed from the handler source files, NOT from the built archive.
  src_files = sort(tolist(fileset(local.src_dir, "**")))
  src_hash  = sha1(join("", [for f in local.src_files : filesha256("${local.src_dir}/${f}")]))
}
