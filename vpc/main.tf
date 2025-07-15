# Set the AWS provider and region
provider "aws" {
  region = "us-east-1"
}

# User-defined variable: name of an existing key pair for EC2 access
variable "aws_key_pair_name" {
  description = "The name of the existing EC2 key pair"
  type        = string
}

# User-defined variable: Amazon Linux 2 AMI ID in the region (e.g., ami-12345)
variable "aws_ami_id" {
  description = "AMI ID for EC2 instance (e.g., Amazon Linux 2)"
  type        = string
}

# --- VPC CREATION ---

resource "aws_vpc" "my_vpc" {
  cidr_block           = "10.0.0.0/16"    # Main network range for VPC
  enable_dns_support   = true            # Enables DNS resolution inside VPC
  enable_dns_hostnames = true            # Enables DNS hostnames for instances

  tags = {
    Name = "MyVPC"
  }
}

# --- INTERNET GATEWAY ---

resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "MyIGW"
  }
}

# --- PUBLIC SUBNETS (in 2 AZs) ---

resource "aws_subnet" "public_1a" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true  # Ensures EC2 in this subnet gets public IP

  tags = { Name = "Public-1A" }
}

resource "aws_subnet" "public_1b" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = { Name = "Public-1B" }
}

# --- PRIVATE SUBNETS ---

resource "aws_subnet" "private_1a" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"

  tags = { Name = "Private-1A" }
}

resource "aws_subnet" "private_1b" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"

  tags = { Name = "Private-1B" }
}

# --- PUBLIC ROUTE TABLE ---

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "Public-RT"
  }
}

# Default route: Internet-bound traffic (0.0.0.0/0) goes through the IGW
resource "aws_route" "public_rt_default" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.my_igw.id
}

# Associate public subnets with the public route table
resource "aws_route_table_association" "public_1a_assoc" {
  subnet_id      = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_1b_assoc" {
  subnet_id      = aws_subnet.public_1b.id
  route_table_id = aws_route_table.public_rt.id
}

# --- PRIVATE ROUTE TABLE ---

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "Private-RT"
  }
}

# Associate private subnets with the private route table
resource "aws_route_table_association" "private_1a_assoc" {
  subnet_id      = aws_subnet.private_1a.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_1b_assoc" {
  subnet_id      = aws_subnet.private_1b.id
  route_table_id = aws_route_table.private_rt.id
}

# --- NAT GATEWAY SETUP (for private subnets to reach internet) ---

# Elastic IP for NAT Gateway (must be created separately)
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

# NAT Gateway in one of the public subnets
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1a.id  # NAT gateway must be in a public subnet

  tags = {
    Name = "MyNATGateway"
  }

  depends_on = [aws_internet_gateway.my_igw]  # Ensure IGW exists first
}

# Route for private subnets to access internet via NAT
resource "aws_route" "private_nat_route" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw.id
}

# --- SECURITY GROUP (for SSH access) ---

resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH access"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Open to world for testing; restrict for production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # Allow all outbound traffic
  }

  tags = {
    Name = "SSH-Access"
  }
}

# --- EC2 INSTANCE IN PUBLIC SUBNET ---

resource "aws_instance" "public_instance" {
  ami                         = var.aws_ami_id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_1a.id
  vpc_security_group_ids      = [aws_security_group.allow_ssh.id]
  associate_public_ip_address = true
  key_name                    = var.aws_key_pair_name

  tags = {
    Name = "Public-Instance"
  }
}

# --- EC2 INSTANCE IN PRIVATE SUBNET ---

resource "aws_instance" "private_instance" {
  ami                         = var.aws_ami_id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.private_1a.id
  vpc_security_group_ids      = [aws_security_group.allow_ssh.id]
  associate_public_ip_address = false  # No public IP; access from public EC2 or SSM
  key_name                    = var.aws_key_pair_name

  tags = {
    Name = "Private-Instance"
  }
}
