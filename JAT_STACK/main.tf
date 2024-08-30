# Configure the AWS provider
provider "aws" {
  region = "us-east-1"
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "JAT_VPC"
  }
}

# Create a public subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = {
    Name = "JAT_Public_Subnet"
  }
}

# Create a private subnet
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = false
  availability_zone       = "us-east-1a"
  tags = {
    Name = "JAT_Private_Subnet"
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "JAT_IGW"
  }
}

# Create a public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "JAT_Public_Route_Table"
  }
}

# Create a route in the public route table
resource "aws_route" "default_route" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Associate the route table with the public subnet
resource "aws_route_table_association" "public_association" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Create a private route table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "JAT_Private_Route_Table"
  }
}

# Associate the private route table with the private subnet
resource "aws_route_table_association" "private_association" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Create a security group for the EC2 instances
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "JAT_SG"
  }
}

# Create the IAM Role
resource "aws_iam_role" "ec2_role" {
  name = "ec2_full_permission_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Attach AdministratorAccess Policy to the IAM Role
resource "aws_iam_role_policy_attachment" "ec2_role_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Create an IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2_instance_profile"
  role = aws_iam_role.ec2_role.name
}

# Create an EC2 key pair
resource "aws_key_pair" "main_key" {
  key_name   = "JAT_Keypair"
  public_key = file("./public_keypair.pub")  # Replace with the path to your public key file
}

# Launch an EC2 instance in the public subnet
resource "aws_instance" "terraform" {
  count         = 1
  ami           = "ami-0a0e5d9c7acc336f1"  # Replace with your desired AMI ID
  instance_type = "t2.micro"               # Replace with your desired instance type
  key_name      = aws_key_pair.main_key.key_name  # Use the created key pair

  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name

  tags = {
    Name = "Terraform_Server"
    Env  = "Terraform_Server"
  }
  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
              echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
              sudo apt update && sudo apt install terraform -y
              cd /home/ubuntu
              wget https://raw.githubusercontent.com/mannem302/download/main/private.pem
              wget https://raw.githubusercontent.com/mannem302/download/main/public_keypair.pub
              sudo chown -R ubuntu:ubuntu /home/ubuntu/
              sudo chmod 400 private.pem
              EOF
}
# Launch an EC2 instance in the public subnet
resource "aws_instance" "ansible" {
  count         = 1
  ami           = "ami-0a0e5d9c7acc336f1"  # Replace with your desired AMI ID
  instance_type = "t2.micro"               # Replace with your desired instance type
  key_name      = aws_key_pair.main_key.key_name  # Use the created key pair

  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name

  tags = {
    Name = "Ansible_Master"
    Env  = "Ansible_Master"
  }
  user_data = <<-EOF
              #!/bin/bash
              export DEBIAN_FRONTEND=noninteractive
              sudo apt update -y
              sudo apt install software-properties-common -y
              sudo add-apt-repository --yes --update ppa:ansible/ansible
              sudo apt update && sudo apt install ansible -y
              sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pip
              pip install boto3 botocore
              sleep 40
              cd /home/ubuntu
              wget https://raw.githubusercontent.com/mannem302/download/main/private.pem
              wget https://raw.githubusercontent.com/mannem302/download/main/public_keypair.pub
              wget https://raw.githubusercontent.com/mannem302/AnilKumar/main/aws_ec2.yml
              wget https://raw.githubusercontent.com/mannem302/download/main/ansible.cfg
              sudo mv ansible.cfg /etc/ansible/ansible.cfg
              sudo chown -R ubuntu:ubuntu /home/ubuntu/
              sudo chmod 400 private.pem
              EOF
}

resource "aws_instance" "jenkins" {
  count         = 1
  ami           = "ami-0a0e5d9c7acc336f1"  # Replace with your desired AMI ID
  instance_type = "t2.small"               # Replace with your desired instance type
  key_name      = aws_key_pair.main_key.key_name  # Use the created key pair

  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name

  tags = {
    Name = "Jenkins_Server"
    Env  = "Jenkins_Server"
  }
  
  user_data = <<-EOF
  #!/bin/bash
  # Update the system
  # Add Docker's official GPG key:
  sudo apt-get update
  sudo apt-get install ca-certificates curl -y
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  # Add the repository to Apt sources:
  echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
  systemctl start docker
  systemctl enable docker
  usermod -aG docker ubuntu
  cd /home/ubuntu
  mkdir docker_jenkins && cd docker_jenkins
  wget https://raw.githubusercontent.com/mannem302/download/main/init.groovy
  wget https://raw.githubusercontent.com/mannem302/download/main/Dockerfile
  wget https://raw.githubusercontent.com/mannem302/download/main/plugins.txt
  sudo chown -R ubuntu:ubuntu /home/ubuntu/
  sudo mkdir -p /var/jenkins_home
  sudo chown -R 1000:1000 /var/jenkins_home
  docker build -t my-jenkins .
  docker run -itd --restart unless-stopped --name jenkins_server --memory="1500m" --cpus=1 -v /var/jenkins_home:/var/jenkins_home -p 8080:8080 my-jenkins
  EOF
}

output "jenkins_url" {
  description = "Jenkins URL"
  value       = "http://${aws_instance.jenkins[0].public_ip}:8080"
}
