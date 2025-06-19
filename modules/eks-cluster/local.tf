locals {
  common_tags = merge(var.tags, {
    env_name = var.env_name
  })
}
