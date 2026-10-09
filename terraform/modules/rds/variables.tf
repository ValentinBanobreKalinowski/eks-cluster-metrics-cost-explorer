variable "name" {
  description = "Name prefix for RDS resources"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Subnets for the DB subnet group - needs at least 2 in different AZs"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to reach Postgres on port 5432"
  type        = list(string)
}

variable "instance_class" {
  description = "Cheap Instance Class"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Storage in GB - 20 is the RDS minimum"
  type        = number
  default     = 20
}

variable "engine_version" {
  type    = string
  default = "17"
}

variable "db_name" {
  type = string
}

variable "username" {
  type      = string
  sensitive = true
}

variable "password" {
  type      = string
  sensitive = true
}
