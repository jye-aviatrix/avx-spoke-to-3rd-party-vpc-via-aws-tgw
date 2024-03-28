# Deploy Aviatrix Transit
module "mc-transit" {
  source        = "terraform-aviatrix-modules/mc-transit/aviatrix"
  version       = "2.5.3"
  cloud         = "AWS"
  account       = var.account
  region        = var.region
  name          = var.transit_vpc_name
  gw_name       = var.transit_gw_name
  cidr          = var.transit_vpc_cidr
  instance_size = var.transit_gw_size
}

# Deploy App Spoke
module "mc-spoke-app" {
  source        = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version       = "1.6.8"
  cloud         = "AWS"
  account       = var.account
  region        = var.region
  name          = var.app_vpc_name
  gw_name       = var.app_gw_name
  cidr          = var.app_vpc_cidr
  transit_gw    = module.mc-transit.transit_gateway.gw_name
  instance_size = var.spoke_gw_size
}

# Deploy test instance in App Spoke VPC zone 1
module "aws-linux-vm-public-app1" {
  source    = "jye-aviatrix/aws-linux-vm-public/aws"
  version   = "2.0.4"
  key_name  = var.key_name
  vm_name   = "app-pub1"
  vpc_id    = module.mc-spoke-app.vpc.vpc_id
  subnet_id = [for s in module.mc-spoke-app.vpc.public_subnets : s if !strcontains(s.name, "Public-1")][0].subnet_id
  use_eip   = true
}

output "app-pub1" {
  value = module.aws-linux-vm-public-app1
}

# Deploy test instance in App Spoke VPC zone 2
module "aws-linux-vm-public-app2" {
  source    = "jye-aviatrix/aws-linux-vm-public/aws"
  version   = "2.0.4"
  key_name  = var.key_name
  vm_name   = "app-pub2"
  vpc_id    = module.mc-spoke-app.vpc.vpc_id
  subnet_id = [for s in module.mc-spoke-app.vpc.public_subnets : s if !strcontains(s.name, "Public-2")][0].subnet_id
  use_eip   = true
}

output "app-pub2" {
  value = module.aws-linux-vm-public-app2
}

# Deploy Connection Spoke
module "mc-spoke-conn" {
  source                           = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version                          = "1.6.8"
  cloud                            = "AWS"
  account                          = var.account
  region                           = var.region
  name                             = var.conn_vpc_name
  gw_name                          = var.conn_gw_name
  cidr                             = var.conn_vpc_cidr
  instance_size                    = var.spoke_gw_size
  transit_gw                       = module.mc-transit.transit_gateway.gw_name
  included_advertised_spoke_routes = "${var.conn_vpc_cidr},${var.sap_vpc_cidr}"
}

module "aws-linux-vm-public-conn" {
  source    = "jye-aviatrix/aws-linux-vm-public/aws"
  version   = "2.0.4"
  key_name  = var.key_name
  vm_name   = "conn-pub"
  vpc_id    = module.mc-spoke-conn.vpc.vpc_id
  subnet_id = [for s in module.mc-spoke-conn.vpc.public_subnets : s if !strcontains(s.name, "Public-1")][0].subnet_id
  use_eip   = true
}

output "conn-pub" {
  value = module.aws-linux-vm-public-conn
}

# Deploy SAP VPC
resource "aviatrix_vpc" "sap_vpc" {
  cloud_type           = 1
  account_name         = var.account
  region               = var.region
  name                 = var.sap_vpc_name
  cidr                 = var.sap_vpc_cidr
  aviatrix_transit_vpc = false
  aviatrix_firenet_vpc = false
}

# Create a test instance on SAP VPC zone 1
module "aws-linux-vm-public-sap1" {
  source    = "jye-aviatrix/aws-linux-vm-public/aws"
  version   = "2.0.4"
  key_name  = var.key_name
  vm_name   = "sap-pub-1"
  vpc_id    = aviatrix_vpc.sap_vpc.vpc_id
  subnet_id = [for s in aviatrix_vpc.sap_vpc.public_subnets : s if !strcontains(s.name, "Public-1")][0].subnet_id
  use_eip   = true
}

output "sap-pub1" {
  value = module.aws-linux-vm-public-sap1
}

# Create a test instance on SAP VPC zone 2
module "aws-linux-vm-public-sap2" {
  source    = "jye-aviatrix/aws-linux-vm-public/aws"
  version   = "2.0.4"
  key_name  = var.key_name
  vm_name   = "sap-pub-2"
  vpc_id    = aviatrix_vpc.sap_vpc.vpc_id
  subnet_id = [for s in aviatrix_vpc.sap_vpc.public_subnets : s if !strcontains(s.name, "Public-2")][0].subnet_id
  use_eip   = true
}

output "sap-pub2" {
  value = module.aws-linux-vm-public-sap2
}

# Create AWS TGW
resource "aws_ec2_transit_gateway" "tgw" {
  description = "tgw"
}

# Attach Conn Spoke VPC to AWS TGW
resource "aws_ec2_transit_gateway_vpc_attachment" "conn_to_tgw" {
  subnet_ids         = [[for s in module.mc-spoke-conn.vpc.private_subnets : s if !strcontains(s.name, "Private-1")][0].subnet_id, [for s in module.mc-spoke-conn.vpc.private_subnets : s if !strcontains(s.name, "Private-2")][0].subnet_id]
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = module.mc-spoke-conn.vpc.vpc_id
}

# Attach SAP VPC to AWS TGW
resource "aws_ec2_transit_gateway_vpc_attachment" "sap_to_tgw" {
  subnet_ids         = [[for s in aviatrix_vpc.sap_vpc.private_subnets : s if !strcontains(s.name, "Private-1")][0].subnet_id, [for s in aviatrix_vpc.sap_vpc.private_subnets : s if !strcontains(s.name, "Private-2")][0].subnet_id]
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = aviatrix_vpc.sap_vpc.vpc_id
}

# Add routes on SAP VPC subnet routes
resource "aws_route" "sap" {
  for_each               = toset(aviatrix_vpc.sap_vpc.route_tables)
  route_table_id         = each.value
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
}

# Add routes to Connect VPC subnet routes
resource "aws_route" "conn" {
  for_each               = toset(module.mc-spoke-conn.vpc.route_tables)
  route_table_id         = each.value
  destination_cidr_block = var.sap_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
}

# Add route to onprem to TGW route table
resource "aws_ec2_transit_gateway_route" "to_onprem" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.conn_to_tgw.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.tgw.association_default_route_table_id
}


# Create smart group for SAP VPC CIDR
resource "aviatrix_smart_group" "sap" {
  name = "sap"
  selector {
    match_expressions {
      cidr = var.sap_vpc_cidr
    }

  }
}

# Create smart group for App Pub VM 1
resource "aviatrix_smart_group" "app_pub1" {
  name = "app-pub1"
  selector {
    match_expressions {
      type = "vm"
      name = "app-pub1"
    }

  }

}

# Create smart group for App Pub VM 2
resource "aviatrix_smart_group" "app_pub2" {
  name = "app-pub2"
  selector {
    match_expressions {
      type = "vm"
      name = "app-pub2"
    }

  }

}

# Create DCF rule
resource "aviatrix_distributed_firewalling_policy_list" "distributed_firewalling_policy_list" {
  policies {
    name   = "app-pub1-to-sap"
    action = "PERMIT"
    src_smart_groups = [
      aviatrix_smart_group.app_pub1.uuid
    ]
    dst_smart_groups = [
      aviatrix_smart_group.sap.uuid
    ]
    logging                  = true
    exclude_sg_orchestration = true
    priority                 = 1
    protocol                 = "ANY"
    watch                    = false
    flow_app_requirement     = "APP_UNSPECIFIED"
    decrypt_policy           = "DECRYPT_UNSPECIFIED"
  }


  policies {
    name   = "app-pub2-to-sap"
    action = "PERMIT"
    src_smart_groups = [
      aviatrix_smart_group.app_pub2.uuid
    ]
    dst_smart_groups = [
      aviatrix_smart_group.sap.uuid
    ]
    logging                  = true
    exclude_sg_orchestration = true
    priority                 = 2
    protocol                 = "ANY"
    watch                    = false
    flow_app_requirement     = "APP_UNSPECIFIED"
    decrypt_policy           = "DECRYPT_UNSPECIFIED"
  }

  policies {
    name   = "deny-inbound-traffic-from-sap"
    action = "DENY"
    src_smart_groups = [
      aviatrix_smart_group.sap.uuid
    ]
    dst_smart_groups = [
      "def000ad-0000-0000-0000-000000000000"
    ]
    logging                  = true
    exclude_sg_orchestration = true
    priority                 = 3
    protocol                 = "ANY"
    watch                    = false
    flow_app_requirement     = "APP_UNSPECIFIED"
    decrypt_policy           = "DECRYPT_UNSPECIFIED"
  }

  policies {
    name   = "deny-outbound-traffic-to-sap"
    action = "DENY"
    src_smart_groups = [
      "def000ad-0000-0000-0000-000000000000"
    ]
    dst_smart_groups = [
      aviatrix_smart_group.sap.uuid
    ]
    logging                  = true
    exclude_sg_orchestration = true
    priority                 = 4
    protocol                 = "ANY"
    watch                    = false
    flow_app_requirement     = "APP_UNSPECIFIED"
    decrypt_policy           = "DECRYPT_UNSPECIFIED"
  }

  policies {
    name   = "Greenfield-Rule"
    action = "PERMIT"
    src_smart_groups = [
      "def000ad-0000-0000-0000-000000000000"
    ]
    dst_smart_groups = [
      "def000ad-0000-0000-0000-000000000000"
    ]
    priority                 = 2147483644
    logging                  = true
    exclude_sg_orchestration = true
    protocol                 = "ANY"
    watch                    = false
    flow_app_requirement     = "APP_UNSPECIFIED"
    decrypt_policy           = "DECRYPT_UNSPECIFIED"
  }

}