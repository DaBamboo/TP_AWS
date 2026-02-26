variable "VPC_ID" {
    type = string
    description = "virtual Private Cloud ID"
}
variable "PRIV1_ID" {
    type = string
    description = "private subnet 1 : 10.0.1.0/24"
}
variable "PRIV2_ID" {
    type = string
    description = "private subnet 2 : 10.0.2.0/24"
}
variable "PUB1_ID" {
    type = string
    description = "public subnet 1 : 10.0.11.0/24"
}
variable "PUB2_ID" {
    type = string
    description = "public subnet 2 : 10.0.12.0/24"
}
variable "SGWEB_ID" {
    type = string
    description = "security group for web servers"
}
variable "SGAPP_ID" {
    type = string
    description = "security group for app servers"  
}
variable "SGDB_ID" {
    type = string
    description = "security group for database servers"  
}
variable "AMI_ID" {
    type = string
    description = "AMI ID for Amazon Linux 2023"
}
variable "INST_ID" {
    type = string
    description = "instance ID of the EC2 instance from TP4"
}

