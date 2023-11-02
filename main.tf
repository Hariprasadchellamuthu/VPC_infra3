provider "aws" {
  region = "us-east-1" # Change to your desired region
}

variable "vpc_cidr_block" {
  type        = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
   type        = list(string)
   default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "azs" {
 type        = list(string)
 description = "Availability Zones"
 default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}



# Create a VPC as per our given CIDR block
resource "aws_vpc" "my_vpc" {
  cidr_block = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "VPC_Pro"
  }
}

# Create a IGW

resource "aws_internet_gateway" "ik" {
  vpc_id = aws_vpc.my_vpc.id
  
}

# create a Public subnets
resource "aws_subnet" "public_subnets" {
 count             = length(var.public_subnet_cidrs)
 vpc_id            = aws_vpc.my_vpc.id
 cidr_block        = element(split(",", var.public_subnet_cidrs[count.index]), 0)
 availability_zone = element(var.azs, count.index)
 map_public_ip_on_launch = true
 
 tags = {
   Name = "${element(var.azs, count.index)}}-public-subnet"
 }
}

# create a Private subnets
resource "aws_subnet" "private_subnets" {
 count             = length(var.private_subnet_cidrs)
 vpc_id            = aws_vpc.my_vpc.id
 cidr_block        = element(split(",", var.private_subnet_cidrs[count.index]), 0)
 availability_zone = element(var.azs, count.index)
 map_public_ip_on_launch = false 
 tags = {
   Name = "${element(var.azs, count.index)}}-private-subnet"
 }
}



# Create a route table for the public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "public-route-table"
  }
}


# Associate each public subnet with its route table
resource "aws_route_table_association" "public_subnet_association" {
  count        = length(var.public_subnet_cidrs)
  subnet_id    = element(aws_subnet.public_subnets.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

# Create a NAT gateway for each public subnet
resource "aws_nat_gateway" "my_nat_gateway" {
  allocation_id = aws_eip.my_eip.id
  subnet_id     = element(aws_subnet.private_subnets.*.id, 0)

tags = {
  Name = "nat"
  }
depends_on = [aws_eip.my_eip]
}

# Create an Elastic
resource "aws_eip" "my_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.ik]
}

# Create a route table for the private subnets (for routing through the NAT gateways)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "private-route-table"
  }
}

#Route for Internet Gateway:

resource "aws_route" "public_internet_gateway" {
  route_table_id          = aws_route_table.public.id
  destination_cidr_block  = "0.0.0.0/0"
  gateway_id              = aws_internet_gateway.ik.id
}

# Add a route to each private subnet route table to route traffic through the corresponding NAT gateway
resource "aws_route" "private_nat_gateway" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.my_nat_gateway.id
}

# Associate each private subnet with its route table
resource "aws_route_table_association" "private_subnet_association" {
  count        = length(var.private_subnet_cidrs)
  subnet_id    = element(aws_subnet.private_subnets.*.id, count.index)
  route_table_id = aws_route_table.private.id
}

# Create security groups for public and private instances
resource "aws_security_group" "public_sg" {
  name        = "public-sg"
  description = "Security group for public instances"
  vpc_id      = aws_vpc.my_vpc.id

  # Define inbound and outbound rules as needed
  # Example: Allow SSH from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
  from_port       = 3306
  to_port         = 3306
  protocol        = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  }
# Egress (outbound) rules
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # Allow all outbound traffic
    cidr_blocks = ["0.0.0.0/0"]  # Allow traffic to all destinations (0.0.0.0/0)
  }
}
data "aws_ami" "ubuntu22" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Determine the number of public subnets
locals {
  num_public_subnets = length(var.public_subnet_cidrs)
}

# Create an EC2 instance in the public subnet
resource "aws_instance" "public_instance" {
  count       = local.num_public_subnets
  ami           = data.aws_ami.ubuntu22.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnets[count.index].id # Change to the desired public subnet index
  security_groups = [aws_security_group.public_sg.id]
  key_name        = "PK1"
  tags = {
    Name = "Public-EC2-Instance"
  }

#EC2 instance is created after the RDS instance 
  depends_on = [aws_db_instance.private_rds]
}

resource "null_resource" "name" {
    count = local.num_public_subnets

    connection {
      type     = "ssh"
      user     = "ubuntu"  # The default username for Ubuntu instances
      host     = element(aws_instance.public_instance.*.public_ip, count.index)
      private_key = file("/home/ubuntu/PEM/PK1.pem")  # Replace with your private key file
    }

    provisioner "file" {
      source      = "/home/ubuntu/Scripts/install_jen.sh"
      destination = "/tmp/install_jen.sh"
    }

    provisioner "remote-exec" {
      inline = [
          "sudo chmod +x /tmp/install_jen.sh",
          "RDS_ENDPOINT=$(terraform output -json aws_db_instance_private_rds | jq -r '..*.endpoint')",
          "sudo sh /tmp/install_jen.sh"
      ]
    }
}

# RDS Private Subnet Group
resource "aws_db_subnet_group" "private_db_subnet" {
  name        = "mysql-rds-private-subnet-group"
  description = "Private subnets for RDS instance"
  subnet_ids = aws_subnet.private_subnets[*].id
}



# Determine the number of public subnets
locals {
  num_private_subnets = length(var.private_subnet_cidrs)
}

# Create an RDS instance if there are two public subnets
resource "aws_db_instance" "private_rds" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  identifier           = "pridatabase"
  username             = "priuser"
  password             = "pripassword"
  parameter_group_name = "default.mysql5.7"
  db_subnet_group_name = aws_db_subnet_group.private_db_subnet.name
  skip_final_snapshot  = true
  publicly_accessible  = true  # Make it publicly accessible if required
  multi_az             = false

  tags = {
    Name = "PrivateRDSInstance"
  }


}

output "aws_db_instance_private_rds" {
  value = aws_db_instance.private_rds
  sensitive = true
}


