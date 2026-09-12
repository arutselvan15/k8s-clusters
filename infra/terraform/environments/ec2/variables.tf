variable "aws_region" {
  type        = string
  description = "From sensitive/aws/cli.conf (scripts pass -var). No default in Terraform."
}

variable "aws_profile" {
  type        = string
  description = "Profile name in k8s-platform/sensitive/aws/credentials."
}

variable "cluster_name" {
  type        = string
  description = "From the cluster id passed to up.sh. Nodes are {cluster_name}-cp and {cluster_name}-wk-N."
}

variable "ssh_private_key_path" {
  type        = string
  description = "Local path for the generated SSH private key (sensitive/<env>/<cluster_name>/ssh.pem)."
}

variable "vpc_cidr" {
  type        = string
  description = "Private IPv4 range for the lab VPC."
}

variable "subnet_newbits" {
  type        = number
  description = "Extra bits for cidrsubnet(vpc_cidr, newbits, netnum). 8 → /24 from a /16."
}

variable "subnet_netnum" {
  type        = number
  description = "Network number for cidrsubnet (1 → first /24 when newbits is 8 on a /16)."
}

variable "admin_cidr" {
  type        = string
  description = "Who may SSH (22) and reach the Kubernetes API (6443)."
}

variable "node_instance_type" {
  type        = string
  description = "EC2 size for control plane and workers."
}

variable "worker_nodes" {
  type        = number
  description = "Worker EC2 count (>= 1). First worker is aws_instance.worker; extras are extra_workers."
}

variable "root_volume_gb" {
  type        = number
  description = "Root EBS size (GiB)."
}

variable "root_volume_type" {
  type        = string
  description = "Root EBS type (for example gp3)."
}

variable "ssh_user" {
  type        = string
  description = "SSH user on the AMI."
}

variable "ami_name" {
  type        = string
  description = "AMI name filter (wildcard allowed)."
}

variable "ami_owner" {
  type        = string
  description = "AMI owner account id (Canonical public id for Ubuntu images)."
}
