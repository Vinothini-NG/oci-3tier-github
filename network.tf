#create vcn
resource "oci_core_vcn" "main_vcn" {
  compartment_id = var.compartment_ocid
  cidr_block     = "10.0.0.0/16"
  display_name   = "main-vcn-github"
  dns_label      = "mainvcn"
}

#create internrt gateway
resource "oci_core_internet_gateway" "main_igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "main-igw-github"
  enabled        = true
}

#create public route table
resource "oci_core_route_table" "public_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "public-rt-github"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main_igw.id
  }
}

# ADDING PUBLIC-SECURITYLIST AND THEIR INGRESS AND EGRESS RULES
resource "oci_core_security_list" "public_security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "public-security-list-tf-github"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"

    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "1"

    icmp_options {
      type = 3
    }
  }
  # Allow HTTP traffic to Load Balancer
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"

    tcp_options {
      min = 80
      max = 80
    }
  }
}

#public subnet
resource "oci_core_subnet" "public_subnet" {
  compartment_id = var.compartment_ocid

  vcn_id = oci_core_vcn.main_vcn.id

  cidr_block   = "10.0.1.0/24"
  display_name = "public-subnet-github"
  dns_label    = "publicsubnet"

  route_table_id = oci_core_route_table.public_rt.id

  security_list_ids = [
    oci_core_security_list.public_security_list.id
  ]

  prohibit_public_ip_on_vnic = false
}

#create bastion host
#CREATE BASTION HOST
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "oracle_linux" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "9"
  shape                    = "VM.Standard.E5.Flex"

  sort_by    = "TIMECREATED"
  sort_order = "DESC"
}

resource "oci_core_instance" "bastion_host" {
  availability_domain = "eaWm:AP-SYDNEY-1-AD-1"
  compartment_id      = var.compartment_ocid
  display_name        = "bastion-host-tf-github"
  shape               = "VM.Standard.E5.Flex"

  shape_config {
    ocpus         = 1
    memory_in_gbs = 12
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public_subnet.id
    assign_public_ip = true
    display_name     = "bastion-vnic"
    hostname_label   = "bastionhost"
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.oracle_linux.images[0].id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    }
}

#CREATING NAT GATEWAY
resource "oci_core_nat_gateway" "private_nat_gateway" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "private-nat-gateway-tf-github"
}

#CREATING SERVICE GATEWAY
resource "oci_core_service_gateway" "service_gateway" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "service-gateway-tf-github"

  services {
    service_id = data.oci_core_services.all_services.services[0].id
  }
}

data "oci_core_services" "all_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

#CREATING PRIVATE ROUTE TABLE
resource "oci_core_route_table" "private_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main_vcn.id
  display_name   = "privateRT-tf-github"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.private_nat_gateway.id
  }

  route_rules {
    destination       = lookup(data.oci_core_services.all_services.services[0], "cidr_block")
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.service_gateway.id
  }
}