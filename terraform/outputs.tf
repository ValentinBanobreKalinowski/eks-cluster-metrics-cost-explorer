output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}
output "ecr_backend_url" {
  value = aws_ecr_repository.backend.repository_url
}
output "ecr_frontend_url" {
  value = aws_ecr_repository.frontend.repository_url
}
output "rds_address" {
  value = module.rds.address
}
output "region" {
  value = var.region
}

output "s3_reports_bucket" {
  value = module.s3_reports.bucket_name
}

output "app_hostname" {
  value = var.app_hostname
}
output "route53_zone_id" {
  value = module.route53.zone_id
}
output "acm_certificate_arn" {
  value = module.route53.certificate_arn
}
output "postgres_app_username" {
  value = var.postgres_app_username
}
