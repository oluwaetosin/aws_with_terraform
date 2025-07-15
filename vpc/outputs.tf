# Output the public IP address of the public instance
output "public_instance_public_ip" {
  value       = aws_instance.public_instance.public_ip
  description = "Public IP address of the public EC2 instance"
}

# Output the private IP address of the private instance
output "private_instance_private_ip" {
  value       = aws_instance.private_instance.private_ip
  description = "Private IP address of the private EC2 instance"
}
