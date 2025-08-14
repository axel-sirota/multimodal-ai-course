variable "aws_region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "g4dn.xlarge" # 1 GPU, 16GB VRAM
}

variable "api_token" {
  description = "Simple token for API access"
  type        = string
  sensitive   = true
  # No default - must be provided via terraform.tfvars
}

variable "ssh_key_name" {
  description = "AWS EC2 Key Pair name for SSH access"
  type        = string
  sensitive   = true
  # No default - must be provided via terraform.tfvars
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH access"
  type        = string
  sensitive   = true
  # No default - must be provided via terraform.tfvars
}