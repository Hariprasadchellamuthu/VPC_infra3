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
