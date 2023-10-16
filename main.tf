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

resource "aws_vpc" "my_vpc" {
  cidr_block = var.vpc_cidr_block

  tags = {
    Name = "VPC_Pro"
  }
}

resource "aws_internet_gateway" "ik" {
  vpc_id = aws_vpc.my_vpc.id
  
}


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
  subnet_id     = element(aws_subnet.public_subnets.*.id, 0)

tags = {
  Name = "nat"
  }
}

# Create an Elastic IP for each NAT gateway
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
}

resource "aws_security_group" "private_sg" {
  name        = "private-sg"
  description = "Security group for private instances"
  vpc_id      = aws_vpc.my_vpc.id

  # Define inbound and outbound rules as needed
  # Example: Allow outbound traffic to the internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Add more rules as needed
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



# Create an EC2 instance in the public subnet
resource "aws_instance" "public_instance" {
  ami           = data.aws_ami.ubuntu22.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnets[0].id # Change to the desired public subnet index
  security_groups = [aws_security_group.public_sg.id]
  key_name        = "PK1"
  tags = {
    Name = "Public-EC2-Instance"
  }
}
resource "null_resource" "name" {

    connection {
      type     = "ssh"
      user     = "ubuntu"  # The default username for Ubuntu instances
      host     = aws_instance.public_instance.public_ip
      private_key = file("/home/ubuntu/PPK/PK1.ppk")  # Replace with your private key file
    }

    provisioner "file" {
      source      = "/home/ubuntu/Scripts/install_jen.sh"
      destination = "/tmp/install_jen.sh"
  }

    provisioner "remote-exec" {
      inline = [
          "sudo chmod +x /tmp/install_jen.sh",
          "sh /tmp/install_jen.sh"
      ]
    }

    depends_on = [aws_instance.public_instance]  
}



# Create an EC2 instance in the private subnet
resource "aws_instance" "private_instance" {
  ami           = "ami-053b0d53c279acc90" # Change to your desired AMI
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private_subnets[0].id # Change to the desired private subnet index
  security_groups = [aws_security_group.private_sg.id]
  tags = {
    Name = "Private-EC2-Instance"
  }

}

output "jenkins_url" {
      value = join ("", ["http://", aws_instance.public_instance.public_ip, ":", "8080"])
}
