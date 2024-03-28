variable "account" {
  description = "Provide Aviatrix access account name"
}

variable "cloud" {
  default = "AWS"
}

variable "region" {
  description = "Provide region of the deployment"
  default     = "us-east-1"
}

variable "transit_gw_size" {
  default = "t3.small"
}

variable "transit_vpc_name" {
  default = "ue1transit"
}

variable "transit_gw_name" {
  default = "ue1transit"
}

variable "transit_vpc_cidr" {
  default = "10.16.0.0/23"
}

variable "app_vpc_name" {
  default = "ue1app1"
}

variable "app_gw_name" {
  default = "ue1app1"
}

variable "app_vpc_cidr" {
  default = "10.32.16.0/24"
}

variable "conn_vpc_name" {
  default = "ue1conn1"
}

variable "conn_gw_name" {
  default = "ue1conn1"
}

variable "conn_vpc_cidr" {
  default = "10.32.32.0/24"
}
variable "spoke_gw_size" {
  default = "t3.small"
}

variable "sap_vpc_name" {
  default = "ue1sap"
}

variable "sap_vpc_cidr" {
  default = "10.64.0.0/24"
}

variable "key_name" {
  description = "Provide EC2 key pair name"
}
