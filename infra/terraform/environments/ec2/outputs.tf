output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "caller_arn" {
  value = data.aws_caller_identity.current.arn
}

output "vpc_id" {
  value = aws_vpc.lab.id
}

output "vpc_cidr" {
  value = aws_vpc.lab.cidr_block
}

output "subnet_id" {
  value = aws_subnet.public.id
}

output "subnet_cidr" {
  value = aws_subnet.public.cidr_block
}

output "availability_zone" {
  value = aws_subnet.public.availability_zone
}

output "internet_gateway_id" {
  value = aws_internet_gateway.lab.id
}

output "security_group_id" {
  value = aws_security_group.lab.id
}

output "admin_cidr" {
  value = var.admin_cidr
}

output "control_plane_public_ip" {
  value = aws_instance.control_plane.public_ip
}

output "control_plane_private_ip" {
  value = aws_instance.control_plane.private_ip
}

output "ssh_private_key_path" {
  value = local_file.ssh_private_key.filename
}

output "ssh_control_plane" {
  value = "ssh -i ${local_file.ssh_private_key.filename} ubuntu@${aws_instance.control_plane.public_ip}"
}

output "worker_public_ip" {
  value       = aws_instance.worker.public_ip
  description = "First worker (kept for SSH examples)."
}

output "worker_private_ip" {
  value = aws_instance.worker.private_ip
}

output "worker_public_ips" {
  value       = join(" ", concat([aws_instance.worker.public_ip], aws_instance.extra_workers[*].public_ip))
  description = "All worker public IPs, space-separated (kubeadm inventory)."
}

output "ssh_worker" {
  value = "ssh -i ${local_file.ssh_private_key.filename} ubuntu@${aws_instance.worker.public_ip}"
}
